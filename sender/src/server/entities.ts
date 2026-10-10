/**
 * Generic entity system (coins, hazards, powerups, zones, obstacles).
 * Modes spawn/remove entities here; the engine syncs them over OSC.
 * Ported from `sender_py/entities.py`.
 */
import type { EntityType, Vec3 } from "../shared/protocol.js";

export class Entity {
  id: number;
  type: EntityType;
  x: number;
  y: number;
  radius: number;
  color: Vec3;
  label: string;
  visible = true;
  needsUpsert = true;

  constructor(
    id: number,
    type: EntityType,
    x: number,
    y: number,
    radius: number,
    color: Vec3,
    label = "",
  ) {
    this.id = id;
    this.type = type;
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.color = color;
    this.label = label;
  }
}

export class EntityManager {
  entities = new Map<number, Entity>();
  removedIds: number[] = [];
  private nextId = 0;

  spawn(type: EntityType, x: number, y: number, radius: number, color: Vec3, label = ""): Entity {
    const e = new Entity(this.nextId, type, x, y, radius, color, label);
    this.nextId += 1;
    this.entities.set(e.id, e);
    return e;
  }

  remove(eid: number): void {
    if (this.entities.delete(eid)) {
      this.removedIds.push(eid);
    }
  }

  clear(): void {
    for (const eid of this.entities.keys()) this.removedIds.push(eid);
    this.entities.clear();
  }

  values(): IterableIterator<Entity> {
    return this.entities.values();
  }
}
