"""Generic entity system (coins, hazards, powerups, zones, obstacles).

Modes spawn/remove entities here; the engine syncs them over OSC. The receiver
renders any entity generically from its type + color.
"""


class Entity:
    def __init__(self, eid, etype, x, y, radius, color, label=""):
        self.id = eid
        self.type = etype
        self.x = x
        self.y = y
        self.radius = radius
        self.color = color          # (r, g, b)
        self.label = label
        self.visible = True
        self.needs_upsert = True


class EntityManager:
    def __init__(self):
        self.entities = {}
        self.removed_ids = []
        self._next_id = 0

    def spawn(self, etype, x, y, radius, color, label=""):
        e = Entity(self._next_id, etype, x, y, radius, color, label)
        self._next_id += 1
        self.entities[e.id] = e
        return e

    def remove(self, eid):
        if eid in self.entities:
            del self.entities[eid]
            self.removed_ids.append(eid)

    def clear(self):
        for eid in list(self.entities.keys()):
            self.removed_ids.append(eid)
        self.entities.clear()

    def values(self):
        return self.entities.values()
