# Убираем проверки Kotlin на null в рантайме — меньше байт-кода
-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    static void checkParameterIsNotNull(...);
    static void checkNotNullParameter(...);
    static void checkNotNullExpressionValue(...);
    static void checkExpressionValueIsNotNull(...);
}
