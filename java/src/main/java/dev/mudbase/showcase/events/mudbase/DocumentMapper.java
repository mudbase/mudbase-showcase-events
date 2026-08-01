package dev.mudbase.showcase.events.mudbase;

import java.util.Map;

/**
 * Converts the SDK's document shapes into a plain {@code Map<String, Object>} keyed the same way
 * as the raw Mudbase JSON ({@code _id}, {@code createdAt}, {@code updatedAt}, plus every
 * collection-defined field), and provides defensive readers for pulling typed values back out.
 * Ported verbatim from the sibling kanban/social/ecommerce showcases.
 */
public final class DocumentMapper {

  private DocumentMapper() {}

  @SuppressWarnings("unchecked")
  public static Map<String, Object> asMap(Object data) {
    if (data == null) {
      return Map.of();
    }
    if (data instanceof Map) {
      return (Map<String, Object>) data;
    }
    throw new IllegalStateException("Expected a JSON object, got: " + data.getClass());
  }

  public static String getId(Map<String, Object> doc) {
    return getString(doc, "_id");
  }

  public static String getString(Map<String, Object> doc, String key) {
    Object value = doc.get(key);
    return value != null ? value.toString() : null;
  }

  public static String getString(Map<String, Object> doc, String key, String fallback) {
    String value = getString(doc, key);
    return value != null && !value.isBlank() ? value : fallback;
  }

  public static long getLong(Map<String, Object> doc, String key, long fallback) {
    Object value = doc.get(key);
    if (value instanceof Number number) {
      return number.longValue();
    }
    if (value instanceof String s && !s.isBlank()) {
      try {
        return Long.parseLong(s);
      } catch (NumberFormatException ignored) {
        return fallback;
      }
    }
    return fallback;
  }

  public static int getInt(Map<String, Object> doc, String key, int fallback) {
    return (int) getLong(doc, key, fallback);
  }
}
