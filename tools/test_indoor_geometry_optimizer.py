import copy
import unittest

from optimize_indoor_geometry import closed_outward, plan_surface, under_sealed_floor

POINTS = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
TETRA = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]


class ConservativeCleanupTests(unittest.TestCase):
    def plan(self, points=POINTS, indices=TETRA, **kwargs):
        options = dict(asset="", node="fixture", material="solid", opaque=True)
        options.update(kwargs)
        return plan_surface(points, indices, points, **options)

    def test_closed_outward_and_engine_winding(self):
        self.assertTrue(closed_outward(POINTS, TETRA)[0])
        reverse = [v for i in range(0, len(TETRA), 3) for v in reversed(TETRA[i:i+3])]
        self.assertFalse(closed_outward(POINTS, reverse)[0])
        self.assertTrue(closed_outward(POINTS, reverse, -1)[0])

    def test_open_and_inconsistent_do_not_cull(self):
        self.assertFalse(self.plan(indices=TETRA[:-3])["can_cull"])
        bad = TETRA[:]
        bad[:3] = reversed(bad[:3])
        self.assertFalse(self.plan(indices=bad)["can_cull"])

    def test_transparency_and_thin_surface_exclusions(self):
        for name in ["glass", "leaf", "hologram", "hair", "water", "screen"]:
            self.assertFalse(self.plan(material=name)["can_cull"])
        self.assertFalse(self.plan(opaque=False)["can_cull"])

    def test_exact_degenerate_and_same_index_duplicate_only(self):
        result = self.plan(indices=TETRA+[0, 0, 1]+TETRA[:3])
        self.assertEqual(result["indices"], TETRA)
        self.assertEqual(result["removed"], {"degenerate": 1, "duplicate": 1, "buried": 0})
        self.assertTrue(result["can_cull"])

    def test_attribute_seam_indices_and_tiny_visible_faces_survive(self):
        points = POINTS + POINTS[:3] + [(0, 0, .00000000001)]
        indices = TETRA + [4, 6, 5] + [0, 1, 7]
        result = self.plan(points, indices)
        self.assertEqual(result["indices"], indices)

    def test_buried_rule_excludes_garden_and_floor_surface(self):
        points = [(-1, -.04, -1), (1, -.04, -1), (0, -.04, 1)]
        self.assertTrue(under_sealed_floor("admissions_studio", "SM_Admissions_Architecture", points))
        self.assertFalse(under_sealed_floor("admissions_studio", "SM_Admissions_Exterior", points))
        self.assertFalse(under_sealed_floor("admissions_studio", "SM_Admissions_Architecture",
                                          [(x, -.014, z) for x, _, z in points]))

    def test_planner_does_not_modify_attributes(self):
        points, indices = copy.deepcopy(POINTS), TETRA[:]
        self.plan(points, indices)
        self.assertEqual(points, POINTS)
        self.assertEqual(indices, TETRA)

    def test_training_only_tile_faces_below_continuous_plinth(self):
        buried = [(-1, -.0205, -1), (1, -.0205, -1), (0, -.0205, 1)]
        for node in ["SM_Architecture_Limestone", "SM_Architecture_Limestone_Alternate"]:
            self.assertTrue(under_sealed_floor("training_runtime", node, buried))
            visible = [(x, -.01, z) for x, _, z in buried]
            self.assertFalse(under_sealed_floor("training_runtime", node, visible))
        self.assertFalse(under_sealed_floor("training_runtime", "SM_Architecture_Deep_Teal_Frame", buried))
        self.assertFalse(under_sealed_floor("training_runtime", "SM_Portal_Limestone", buried))


if __name__ == "__main__":
    unittest.main()
