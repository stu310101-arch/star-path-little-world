# Modern city assets — 2026-09-24

- Kenney City Kit Commercial 2.1, CC0: https://kenney.nl/assets/city-kit-commercial
  Original verified ZIP: `assets/source/urban/kenney-city-commercial.zip` at repository root.
  Original license: `game/assets/kenney/commercial/License.txt`.
  Selected detailed buildings are capped to individual lot footprints, reoriented toward streets, given matte material tints and separate foundations. The originals are retained.
- Kenney Car Kit 3.1, CC0: https://kenney.nl/assets/car-kit
  Original verified ZIP: `assets/source/urban/kenney-cars.zip` at repository root.
  Sedan, hatchback-sports and SUV are used; license copied alongside these GLBs.
  Runtime scale is 2.25 m length, matching the miniature streets. Wheels rotate and the cars follow the outer lane, yielding to the player and the car ahead. This is ambient traffic, not a driveable vehicle simulation.

Town planning is authored in `game/data/districts.json` (`urban_buildings`: role, footprint limit, orientation, position), and built by `game/tools/urban_design.gd`. Traffic is in `game/scripts/city_traffic.gd`.
