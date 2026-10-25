/// Нормализация строки для поиска: регистр, пробелы по краям и «ё» → «е»,
/// чтобы «Жим лежа» находил «Жим лёжа» и наоборот.
String normalizeForSearch(String value) =>
    value.trim().toLowerCase().replaceAll('ё', 'е');
