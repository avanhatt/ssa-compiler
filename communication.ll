; ModuleID = 'src/communication.c'
source_filename = "src/communication.c"
target datalayout = "e-m:o-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-apple-macosx10.13.0"

%struct.Comm = type { i32, double, %struct.Comm* }
%struct._opaque_pthread_rwlock_t = type { i64, [192 x i8] }
%struct._opaque_pthread_rwlockattr_t = type { i64, [16 x i8] }
%struct._opaque_pthread_t = type { i64, %struct.__darwin_pthread_handler_rec*, [8176 x i8] }
%struct.__darwin_pthread_handler_rec = type { void (i8*)*, i8*, %struct.__darwin_pthread_handler_rec* }
%struct.Context = type { %struct.Comm*, %struct._opaque_pthread_rwlock_t }
%struct._opaque_pthread_attr_t = type { i64, [56 x i8] }

@.str = private unnamed_addr constant [16 x i8] c"thread id = %d\0A\00", align 1
@.str.1 = private unnamed_addr constant [24 x i8] c"_find_channel loop: %d\0A\00", align 1
@.str.2 = private unnamed_addr constant [26 x i8] c"_find_channel return: %d\0A\00", align 1
@.str.3 = private unnamed_addr constant [9 x i8] c"send:%d\0A\00", align 1
@.str.4 = private unnamed_addr constant [16 x i8] c"send return:%d\0A\00", align 1
@.str.5 = private unnamed_addr constant [13 x i8] c"receive: %d\0A\00", align 1
@.str.6 = private unnamed_addr constant [21 x i8] c"receive: %d, return\0A\00", align 1

; Function Attrs: nounwind ssp uwtable
define i8* @init() local_unnamed_addr #0 {
  %1 = tail call i8* @malloc(i64 208) #4
  %2 = bitcast i8* %1 to %struct.Comm**
  store %struct.Comm* null, %struct.Comm** %2, align 8, !tbaa !3
  %3 = getelementptr inbounds i8, i8* %1, i64 8
  %4 = bitcast i8* %3 to %struct._opaque_pthread_rwlock_t*
  %5 = tail call i32 @"\01_pthread_rwlock_init"(%struct._opaque_pthread_rwlock_t* nonnull %4, %struct._opaque_pthread_rwlockattr_t* null) #5
  ret i8* %1
}

; Function Attrs: nounwind allocsize(0)
declare noalias i8* @malloc(i64) local_unnamed_addr #1

declare i32 @"\01_pthread_rwlock_init"(%struct._opaque_pthread_rwlock_t*, %struct._opaque_pthread_rwlockattr_t*) local_unnamed_addr #2

; Function Attrs: nounwind ssp uwtable
define noalias i8* @_call_function(i8* nocapture readonly) #0 {
  %2 = tail call %struct._opaque_pthread_t* @pthread_self() #5
  %3 = ptrtoint %struct._opaque_pthread_t* %2 to i64
  %4 = trunc i64 %3 to i32
  %5 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([16 x i8], [16 x i8]* @.str, i64 0, i64 0), i32 %4)
  %6 = bitcast i8* %0 to void (%struct.Context*)**
  %7 = load void (%struct.Context*)*, void (%struct.Context*)** %6, align 8, !tbaa !10
  %8 = getelementptr inbounds i8, i8* %0, i64 8
  %9 = bitcast i8* %8 to %struct.Context**
  %10 = load %struct.Context*, %struct.Context** %9, align 8, !tbaa !12
  tail call void %7(%struct.Context* %10) #5
  ret i8* null
}

; Function Attrs: nounwind
declare i32 @printf(i8* nocapture readonly, ...) local_unnamed_addr #3

declare %struct._opaque_pthread_t* @pthread_self() local_unnamed_addr #2

; Function Attrs: nounwind ssp uwtable
define i8* @call_partitioned_functions(i32, void (i8*)** nocapture readonly, i8*) local_unnamed_addr #0 {
  %4 = sext i32 %0 to i64
  %5 = shl nsw i64 %4, 3
  %6 = tail call i8* @malloc(i64 %5) #4
  %7 = bitcast i8* %6 to %struct._opaque_pthread_t**
  %8 = icmp sgt i32 %0, 0
  br i1 %8, label %9, label %11

; <label>:9:                                      ; preds = %3
  %10 = zext i32 %0 to i64
  br label %12

; <label>:11:                                     ; preds = %12, %3
  ret i8* %6

; <label>:12:                                     ; preds = %12, %9
  %13 = phi i64 [ 0, %9 ], [ %23, %12 ]
  %14 = tail call i8* @malloc(i64 16) #4
  %15 = getelementptr inbounds void (i8*)*, void (i8*)** %1, i64 %13
  %16 = bitcast void (i8*)** %15 to i64*
  %17 = load i64, i64* %16, align 8, !tbaa !13
  %18 = bitcast i8* %14 to i64*
  store i64 %17, i64* %18, align 8, !tbaa !10
  %19 = getelementptr inbounds i8, i8* %14, i64 8
  %20 = bitcast i8* %19 to i8**
  store i8* %2, i8** %20, align 8, !tbaa !12
  %21 = getelementptr inbounds %struct._opaque_pthread_t*, %struct._opaque_pthread_t** %7, i64 %13
  %22 = tail call i32 @pthread_create(%struct._opaque_pthread_t** %21, %struct._opaque_pthread_attr_t* null, i8* (i8*)* nonnull @_call_function, i8* %14) #5
  %23 = add nuw nsw i64 %13, 1
  %24 = icmp eq i64 %23, %10
  br i1 %24, label %11, label %12
}

declare i32 @pthread_create(%struct._opaque_pthread_t**, %struct._opaque_pthread_attr_t*, i8* (i8*)*, i8*) local_unnamed_addr #2

; Function Attrs: nounwind ssp uwtable
define void @join_partitioned_functions(i32, i8* nocapture readonly) local_unnamed_addr #0 {
  %3 = bitcast i8* %1 to %struct._opaque_pthread_t**
  %4 = icmp sgt i32 %0, 0
  br i1 %4, label %5, label %7

; <label>:5:                                      ; preds = %2
  %6 = zext i32 %0 to i64
  br label %8

; <label>:7:                                      ; preds = %8, %2
  ret void

; <label>:8:                                      ; preds = %8, %5
  %9 = phi i64 [ 0, %5 ], [ %13, %8 ]
  %10 = getelementptr inbounds %struct._opaque_pthread_t*, %struct._opaque_pthread_t** %3, i64 %9
  %11 = load %struct._opaque_pthread_t*, %struct._opaque_pthread_t** %10, align 8, !tbaa !13
  %12 = tail call i32 @"\01_pthread_join"(%struct._opaque_pthread_t* %11, i8** null) #5
  %13 = add nuw nsw i64 %9, 1
  %14 = icmp eq i64 %13, %6
  br i1 %14, label %7, label %8
}

declare i32 @"\01_pthread_join"(%struct._opaque_pthread_t*, i8**) local_unnamed_addr #2

; Function Attrs: nounwind ssp uwtable
define void @_add_channel(double, i32, %struct.Context* nocapture) local_unnamed_addr #0 {
  %4 = getelementptr inbounds %struct.Context, %struct.Context* %2, i64 0, i32 0
  %5 = load %struct.Comm*, %struct.Comm** %4, align 8, !tbaa !3
  %6 = icmp eq %struct.Comm* %5, null
  br i1 %6, label %12, label %7

; <label>:7:                                      ; preds = %3, %7
  %8 = phi %struct.Comm* [ %10, %7 ], [ %5, %3 ]
  %9 = getelementptr inbounds %struct.Comm, %struct.Comm* %8, i64 0, i32 2
  %10 = load %struct.Comm*, %struct.Comm** %9, align 8, !tbaa !14
  %11 = icmp eq %struct.Comm* %10, null
  br i1 %11, label %12, label %7

; <label>:12:                                     ; preds = %7, %3
  %13 = tail call i8* @malloc(i64 24) #4
  %14 = bitcast i8* %13 to i32*
  store i32 %1, i32* %14, align 8, !tbaa !18
  %15 = getelementptr inbounds i8, i8* %13, i64 8
  %16 = bitcast i8* %15 to double*
  store double %0, double* %16, align 8, !tbaa !19
  %17 = getelementptr inbounds i8, i8* %13, i64 16
  %18 = bitcast i8* %17 to %struct.Comm**
  store %struct.Comm* null, %struct.Comm** %18, align 8, !tbaa !14
  %19 = bitcast %struct.Context* %2 to i8**
  store i8* %13, i8** %19, align 8, !tbaa !3
  ret void
}

; Function Attrs: nounwind ssp uwtable
define double* @_find_channel(i32, %struct.Context* nocapture readonly) local_unnamed_addr #0 {
  %3 = getelementptr inbounds %struct.Context, %struct.Context* %1, i64 0, i32 0
  %4 = load %struct.Comm*, %struct.Comm** %3, align 8, !tbaa !13
  %5 = icmp eq %struct.Comm* %4, null
  br i1 %5, label %19, label %6

; <label>:6:                                      ; preds = %2, %15
  %7 = phi %struct.Comm* [ %17, %15 ], [ %4, %2 ]
  %8 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([24 x i8], [24 x i8]* @.str.1, i64 0, i64 0), i32 %0)
  %9 = getelementptr inbounds %struct.Comm, %struct.Comm* %7, i64 0, i32 0
  %10 = load i32, i32* %9, align 8, !tbaa !18
  %11 = icmp eq i32 %10, %0
  br i1 %11, label %12, label %15

; <label>:12:                                     ; preds = %6
  %13 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([26 x i8], [26 x i8]* @.str.2, i64 0, i64 0), i32 %0)
  %14 = getelementptr inbounds %struct.Comm, %struct.Comm* %7, i64 0, i32 1
  br label %19

; <label>:15:                                     ; preds = %6
  %16 = getelementptr inbounds %struct.Comm, %struct.Comm* %7, i64 0, i32 2
  %17 = load %struct.Comm*, %struct.Comm** %16, align 8, !tbaa !13
  %18 = icmp eq %struct.Comm* %17, null
  br i1 %18, label %19, label %6

; <label>:19:                                     ; preds = %15, %2, %12
  %20 = phi double* [ %14, %12 ], [ null, %2 ], [ null, %15 ]
  ret double* %20
}

; Function Attrs: nounwind ssp uwtable
define void @send(double, i32, i32, i8*) local_unnamed_addr #0 {
  %5 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([9 x i8], [9 x i8]* @.str.3, i64 0, i64 0), i32 %2)
  %6 = bitcast i8* %3 to %struct.Context*
  %7 = getelementptr inbounds i8, i8* %3, i64 8
  %8 = bitcast i8* %7 to %struct._opaque_pthread_rwlock_t*
  %9 = tail call i32 @"\01_pthread_rwlock_wrlock"(%struct._opaque_pthread_rwlock_t* nonnull %8) #5
  tail call void @_add_channel(double %0, i32 %2, %struct.Context* %6)
  %10 = tail call i32 @"\01_pthread_rwlock_unlock"(%struct._opaque_pthread_rwlock_t* nonnull %8) #5
  %11 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([16 x i8], [16 x i8]* @.str.4, i64 0, i64 0), i32 %2)
  ret void
}

declare i32 @"\01_pthread_rwlock_wrlock"(%struct._opaque_pthread_rwlock_t*) local_unnamed_addr #2

declare i32 @"\01_pthread_rwlock_unlock"(%struct._opaque_pthread_rwlock_t*) local_unnamed_addr #2

; Function Attrs: nounwind ssp uwtable
define double @receive(i32, i32, i8*) local_unnamed_addr #0 {
  %4 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([13 x i8], [13 x i8]* @.str.5, i64 0, i64 0), i32 %1)
  %5 = bitcast i8* %2 to %struct.Context*
  %6 = getelementptr inbounds i8, i8* %2, i64 8
  %7 = bitcast i8* %6 to %struct._opaque_pthread_rwlock_t*
  %8 = tail call i32 @"\01_pthread_rwlock_rdlock"(%struct._opaque_pthread_rwlock_t* nonnull %7) #5
  %9 = tail call double* @_find_channel(i32 %1, %struct.Context* %5)
  %10 = tail call i32 @"\01_pthread_rwlock_unlock"(%struct._opaque_pthread_rwlock_t* nonnull %7) #5
  %11 = icmp eq double* %9, null
  br i1 %11, label %12, label %20

; <label>:12:                                     ; preds = %3, %12
  %13 = tail call i32 @rand() #5
  %14 = srem i32 %13, 2
  %15 = tail call i32 @"\01_sleep"(i32 %14) #5
  %16 = tail call i32 @"\01_pthread_rwlock_rdlock"(%struct._opaque_pthread_rwlock_t* nonnull %7) #5
  %17 = tail call double* @_find_channel(i32 %1, %struct.Context* %5)
  %18 = tail call i32 @"\01_pthread_rwlock_unlock"(%struct._opaque_pthread_rwlock_t* nonnull %7) #5
  %19 = icmp eq double* %17, null
  br i1 %19, label %12, label %20

; <label>:20:                                     ; preds = %12, %3
  %21 = phi double* [ %9, %3 ], [ %17, %12 ]
  %22 = tail call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([21 x i8], [21 x i8]* @.str.6, i64 0, i64 0), i32 %1)
  %23 = load double, double* %21, align 8, !tbaa !20
  ret double %23
}

declare i32 @"\01_pthread_rwlock_rdlock"(%struct._opaque_pthread_rwlock_t*) local_unnamed_addr #2

declare i32 @"\01_sleep"(i32) local_unnamed_addr #2

declare i32 @rand() local_unnamed_addr #2

attributes #0 = { nounwind ssp uwtable "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "less-precise-fpmad"="false" "min-legal-vector-width"="0" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-jump-tables"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #1 = { nounwind allocsize(0) "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #2 = { "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #3 = { nounwind "correctly-rounded-divide-sqrt-fp-math"="false" "disable-tail-calls"="false" "less-precise-fpmad"="false" "no-frame-pointer-elim"="true" "no-frame-pointer-elim-non-leaf" "no-infs-fp-math"="false" "no-nans-fp-math"="false" "no-signed-zeros-fp-math"="false" "no-trapping-math"="false" "stack-protector-buffer-size"="8" "target-cpu"="penryn" "target-features"="+cx16,+fxsr,+mmx,+sahf,+sse,+sse2,+sse3,+sse4.1,+ssse3,+x87" "unsafe-fp-math"="false" "use-soft-float"="false" }
attributes #4 = { allocsize(0) }
attributes #5 = { nounwind }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"PIC Level", i32 2}
!2 = !{!"clang version 8.0.0 (tags/RELEASE_800/final)"}
!3 = !{!4, !5, i64 0}
!4 = !{!"Context", !5, i64 0, !8, i64 8}
!5 = !{!"any pointer", !6, i64 0}
!6 = !{!"omnipotent char", !7, i64 0}
!7 = !{!"Simple C/C++ TBAA"}
!8 = !{!"_opaque_pthread_rwlock_t", !9, i64 0, !6, i64 8}
!9 = !{!"long", !6, i64 0}
!10 = !{!11, !5, i64 0}
!11 = !{!"Closure", !5, i64 0, !5, i64 8}
!12 = !{!11, !5, i64 8}
!13 = !{!5, !5, i64 0}
!14 = !{!15, !5, i64 16}
!15 = !{!"Comm", !16, i64 0, !17, i64 8, !5, i64 16}
!16 = !{!"int", !6, i64 0}
!17 = !{!"double", !6, i64 0}
!18 = !{!15, !16, i64 0}
!19 = !{!15, !17, i64 8}
!20 = !{!17, !17, i64 0}
