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

// ============================ ENTITY SYSTEM ============================
// Generic world objects (coins, enemies, powerups, zones, obstacles) that the
// receiver renders from type + color. Modes spawn/remove entities here; the
// engine syncs them over OSC (see Core_Osc.pde). Adding a new entity type only
// needs a matching shape in the receiver's ENTITY_SHAPES table -- no per-mode
// receiver code.

class Entity {
  int id;
  String type;      // "coin" | "enemy" | "powerup" | "zone" | "obstacle"
  float x, y;       // mm
  float radius;     // mm (visual size; hitboxes are mode-side)
  color c;
  boolean visible = true;
  boolean needsUpsert = true;   // send /ent/upsert on next sync

  Entity(int id, String type, float x, float y, float radius, color c) {
    this.id = id;
    this.type = type;
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.c = c;
  }
}

HashMap<Integer, Entity> entities = new HashMap<Integer, Entity>();
HashSet<Integer> removedEntityIds = new HashSet<Integer>();
int nextEntityId = 0;

Entity spawnEntity(String type, float x, float y, float radius, color c) {
  Entity e = new Entity(nextEntityId++, type, x, y, radius, c);
  entities.put(e.id, e);
  return e;
}

void removeEntity(int id) {
  if (entities.containsKey(id)) {
    entities.remove(id);
    removedEntityIds.add(id);
  }
}

void clearEntities() {
  for (Integer id : entities.keySet()) removedEntityIds.add(id);
  entities.clear();
}
