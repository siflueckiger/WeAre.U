// ============================ SHARED ENTITY HELPERS ============================
// Mode-agnostic helpers used by all modes. Modes must never hardcode field
// dimensions -- always derive from the anchor geometry, since the field size
// changes per venue (3x7m one day, 7x7m the next).

boolean inZone(TagData t, float[] zone) {
  return t != null && t.pos != null && dist(t.pos.x, t.pos.y, zone[0], zone[1]) < START_ZONE_RADIUS_MM;
}

// Field bounds in mm from the anchor geometry: { minX, maxX, minY, maxY }.
float[] fieldBounds() {
  return new float[] { min(AX), max(AX), min(AY), max(AY) };
}
