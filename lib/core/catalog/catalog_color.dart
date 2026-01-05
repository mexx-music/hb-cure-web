// Helper enum for catalog color used by visibility rules
enum CatalogColor { green, yellow }

CatalogColor catalogColorFromJson(dynamic v) {
  if (v == null) return CatalogColor.green;
  final s = v is String ? v.trim().toLowerCase() : v.toString().trim().toLowerCase();
  return s == 'yellow' ? CatalogColor.yellow : CatalogColor.green;
}

