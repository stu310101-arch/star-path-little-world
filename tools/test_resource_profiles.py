import unittest
from copy import deepcopy
from split_web_packs import Pack, plan_pack, pack_dependency_closure

class ProfileIsolationTests(unittest.TestCase):
    def fixture(self):
        payload = {"project.binary": b"project", "shell.gdc": b"shell", "full.scn": b"full world", "detail.scn": b"full detail", "low.scn": b"low world", "shared.res": b"common", "full.res": b"full-only texture"}
        inventory = {"version":1, "engine":{"major":4,"minor":7,"patch":2}, "errors":[],
                     "groups":{"boot":["res://shell.gd"],"world_full":["res://full.scn"],"district":["res://detail.scn"],"world_low":["res://low.scn"]},
                     "profiles":{"full":["world_full","district"],"low":["world_low"]},
                     "dependencies":{"res://shell.gd":[],"res://full.scn":["res://shared.res","res://full.res"],"res://detail.scn":["res://shared.res","res://full.res"],"res://low.scn":["res://shared.res"],"res://shared.res":[],"res://full.res":[]}}
        payload["shell.gd.remap"] = b'[remap]\npath="res://shell.gdc"\n'
        return Pack((4,7,2),{k:memoryview(v) for k,v in payload.items()}),inventory

    def test_low_closure_cannot_download_full_geometry_or_full_shared_textures(self):
        pack,inventory=self.fixture()
        contents,deps,resources,_=plan_pack(pack,inventory)
        closure=pack_dependency_closure("world_low",deps,set(contents))
        low=set().union(*(set(contents[key]) for key in closure))
        self.assertEqual(low,{"low.scn","shared.res"})
        self.assertEqual(resources["res://full.res"],"shared_full")

    def test_full_profile_still_has_every_original_payload(self):
        pack,inventory=self.fixture()
        contents,deps,_,_=plan_pack(pack,inventory)
        keys=pack_dependency_closure("world_full",deps,set(contents))|pack_dependency_closure("district",deps,set(contents))
        merged={name:bytes(value) for key in keys for name,value in contents[key].items()}
        self.assertEqual(merged,{name:bytes(pack.entries[name]) for name in ("full.scn","detail.scn","shared.res","full.res")})

    def test_byte_alias_deduplication_does_not_leak_other_full_assets_into_low(self):
        pack,inventory=self.fixture()
        pack.entries["alias.res"]=pack.entries["shared.res"]
        inventory["dependencies"]["res://alias.res"]=[]
        inventory["dependencies"]["res://detail.scn"].append("res://alias.res")
        contents,deps,_,_=plan_pack(pack,inventory)
        low=pack_dependency_closure("world_low",deps,set(contents))
        names=set().union(*(set(contents[key]) for key in low))
        self.assertNotIn("full.res",names)
        self.assertNotIn("full.scn",names)

    def test_optional_shared_timing_preserves_existing_physical_ownership(self):
        pack, inventory = self.fixture()
        pack.entries["room.scn"] = memoryview(b"complete optional room")
        inventory["groups"]["counseling_room"] = ["res://room.scn"]
        inventory["dependencies"]["res://room.scn"] = ["res://full.res", "res://shared.res"]
        old = deepcopy(inventory)
        for members in old["profiles"].values():
            members.append("counseling_room")
        previous, previous_deps, previous_resources, _ = plan_pack(pack, old)
        inventory["shared_on_demand"] = ["counseling_room"]
        current, deps, resources, _ = plan_pack(pack, inventory)
        self.assertEqual(current, previous)
        self.assertEqual(deps, previous_deps)
        self.assertEqual(resources, previous_resources)
        for roots in inventory["profiles"].values():
            closure = set().union(*(pack_dependency_closure(key, deps, set(current)) for key in roots))
            self.assertNotIn("counseling_room", closure)

if __name__=='__main__': unittest.main()
