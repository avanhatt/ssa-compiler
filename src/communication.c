#include <pthread.h> 
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

typedef struct Comm Comm;
struct Comm {
    int id;
    double value;
    Comm *next;
};

typedef struct Context Context;
struct Context {
    Comm *channelList;
    pthread_rwlock_t lock;
};

typedef struct Closure Closure;
struct Closure {
    void (*function)(Context *);
    Context *context;
};

void *init() {
    Context *context = malloc(sizeof(Context));
    context->channelList = NULL;
    pthread_rwlock_init(&context->lock, 0);
    return context;
}

void *_call_function(void *function) {
    printf("calling function with thread id = %d\n", (int)pthread_self()); 
    Closure *closure = (Closure *)function;
    void (*fun)(Context *) = closure->function;
    Context *context = closure->context;
    (*fun)(context);
    return NULL;
}

void *call_partitioned_functions(int num_functions, void (**function_pts)(void *), void *context) {
    pthread_t *threads = malloc(sizeof(pthread_t) * num_functions);

    for (int i = 0; i < num_functions; i++) {
        Closure *closure = malloc(sizeof(Closure));
        closure->function = (void (*)(Context *))function_pts[i];
        closure->context = context;
        pthread_create(&threads[i], NULL, _call_function, closure);
    }
    return threads;
}

void join_partitioned_functions(int num_functions, void *threads_arg) {
    pthread_t *threads = (pthread_t *)threads_arg;

    for (int i = 0; i < num_functions; i++) {
        pthread_join(threads[i], NULL);
    }
}

void _add_channel(double value, int id, Context *context) {
    Comm *new = malloc(sizeof(Comm));
    new->id = id;
    new->value = value;
    new->next = NULL;

    Comm *node = context->channelList;
    if (!node) {
        context->channelList = new;
    } else {
        while (node->next) {
            node = node->next;
        }
        node->next = new;
    }
}

double *_find_channel(int id, Context *context) {
    Comm *node = context->channelList;

    while (node) {
        if (id == node->id) {
            // TODO: remove from the list
            return &node->value;
        }
        node = node->next;
    }
    return NULL;
}

void send(double value, int to_core, int id, void *context) {
    Context *c = (Context *)context;
    pthread_rwlock_wrlock(&c->lock);
    _add_channel(value, id, c);
    pthread_rwlock_unlock(&c->lock);
}

double receive(int from_core, int id, void *context) {
    Context *c = (Context *)context;
    while (1) {
        pthread_rwlock_rdlock(&c->lock);
        double *value = _find_channel(id, c);
        pthread_rwlock_unlock(&c->lock);
        if (value) {
            return *value;
        }
    }
    return 0.0;
}