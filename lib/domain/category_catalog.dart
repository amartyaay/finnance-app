import 'enums.dart';

/// The category names the app ships with, mapped to their icon/colour family.
///
/// One catalogue, used by the database seed, the categoriser and the UI pickers,
/// so a category can never exist in one place and be unknown in another.
const Map<String, SpendCategoryKind> categoryCatalog = {
  'Food & dining': SpendCategoryKind.food,
  'Groceries': SpendCategoryKind.groceries,
  'Transport': SpendCategoryKind.transport,
  'Shopping': SpendCategoryKind.shopping,
  'Bills & utilities': SpendCategoryKind.bills,
  'Rent': SpendCategoryKind.rent,
  'Entertainment': SpendCategoryKind.entertainment,
  'Health': SpendCategoryKind.health,
  'Education': SpendCategoryKind.education,
  'Travel': SpendCategoryKind.travel,
  'Fuel': SpendCategoryKind.fuel,
  'Investments': SpendCategoryKind.investments,
  'Transfers': SpendCategoryKind.transfers,
  'Income': SpendCategoryKind.income,
  'Cash': SpendCategoryKind.cash,
  'Other': SpendCategoryKind.other,
};

SpendCategoryKind categoryKindFor(String name) =>
    categoryCatalog[name] ?? SpendCategoryKind.other;
