# goldsrc_nav: the .nav of GoldSrc bots for Mirai

A plugin for the Mirai engine editor that reads and writes the `.nav` files of the bots of GoldSrc
(Counter-Strike 1.6, Condition Zero) as JSON, through methods of the editor API and so of its MCP
server: an agent reads the navigation of a map, edits it and writes the `.nav` back without touching binary.

The engine builds its own navigation mesh from the geometry (the `navigation` plugin). This is the data
of the bots of GoldSrc: its areas, connections, hiding spots, approaches, encounters and places, for a game
that ports those bots or a map that keeps their data.

## Install

It is not in the catalog: nothing in the engine reads a `.nav`. Install it by its address:

```sh
mirai plugin add https://github.com/5hif7y/mirai-goldsrc-nav.git
```

It is the base of a tool to come that converts the navigation of GoldSrc NPCs to Mirai.

## API

- `goldsrc_nav.to_json {path, out}`: a `.nav` anywhere on disk to JSON in the project.
- `goldsrc_nav.to_nav {path, out}`: that JSON, edited or not, back to a `.nav` in the project.
- `goldsrc_nav.summary {path}`: what a `.nav` holds and its bounds, without writing anything.

Each returns the counts of the file: areas, connections, hiding spots, approaches, encounters and places.

## The format

As `game_shared/bot/nav_file.cpp` of ReGameDLL_CS writes it, up to version 5: the magic `0xFEEDFACE`, the
version, the size of the BSP it was made for, the table of places, and each area with its id, flags
(`crouch`, `jump`, `precise`, `no_jump`), extent, the heights of two corners, its connections north, east,
south and west, its hiding spots, its approach entries, its encounter paths and its place. The JSON keeps
the same information in the order of the file, with flags and ways of traversing by name, and keeps what
some editors leave after the areas, so writing what was read gives back the same bytes.

The JSON is the one of `nav2json.py` of the Counter-Strike demo for Mirai: a file written by either reads
in the other.

## Measured

Against the `.nav` of de_dust2 (1 319 areas, 5 212 connections, 516 hiding spots, 22 352 encounters) and of
fy_pool_day (127 areas), which are not in the repository: read and written back, both give the same bytes,
and the JSON that `nav2json.py` writes of de_dust2 gives the same `.nav`.

## Tests

With `mirai test plugins/goldsrc_nav/editor/navfile`. The `.nav` of the tests is written by the tests.

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
