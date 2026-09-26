# Third-Party Notices

## Pokemon intellectual property

Pokemon and all related names, characters, creatures, moves, items, types,
sprites, music, sound effects and other assets are the intellectual property
and/or registered trademarks of **Nintendo**, **Creatures Inc.**, **GAME FREAK
inc.** and **The Pokemon Company**.

This mod is an **unofficial, free, fan-made project** for the
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) engine. It is **not**
produced, affiliated with, sponsored by, endorsed by or approved by Nintendo,
Creatures Inc., GAME FREAK inc., The Pokemon Company or any of their
subsidiaries or affiliates, and it claims no ownership of, or licence to, any
Pokemon intellectual property. The Pokemon names and other marks it reads or
displays remain the property of their owners and are used only to describe the
game data the mod operates on.

## This mod's own work

The only material this project owns is its **original source code** -- the Lua
that hooks the gen1recomp engine, written by its author. That code is licensed
under the **GNU General Public License, version 3 or later (GPL-3.0-or-later)**,
copyright (C) 2026 **tectorifter** (<https://github.com/tectorifter/>); the full
licence text ships beside this file as `LICENSE`. That grant covers this
project's own code only -- it does **not** purport to license any Pokemon data,
artwork, audio, text or other game asset, which remain their owners' property.

## Third-party material

- **Saira fonts** (`assets/fonts/Saira-Regular.ttf`,
  `Saira-SemiBold.ttf`) -- SIL Open Font License 1.1, copyright 2020 The Saira
  Project Authors (<https://github.com/Omnibus-Type/Saira>); the full licence
  ships as `assets/fonts/OFL.txt`. `assets/fonts/g9-symbols.ttf` is generated
  by this project.
- **national_dex** is an optional dependency, not bundled; it supplies the
  species / evolution data this mod drives.
- **Form and evolution names** (Mega, regional forms, Gigantamax, Tera) follow
  the naming used by **Pokemon Showdown**'s and **PokeAPI**'s public data sets;
  the names themselves remain Pokemon IP.

## Sources and credits

- **national_dex** (<https://github.com/sanjinpepic/gen1recomp-national-dex>) --
  the optional species / evolution data source this mod drives.
- **PokeAPI** (<https://github.com/PokeAPI/pokeapi>) -- the evolution methods,
  condition names and item slugs this mod reads are PokeAPI-derived through
  national_dex. PokeAPI is under the **BSD 3-Clause License**, copyright
  (c) 2013-2023 Paul Hallett and PokéAPI contributors.
- **Pokemon Showdown** (<https://github.com/smogon/pokemon-showdown>) -- the
  form / evolution naming conventions followed; MIT License.
- **Noto Sans Symbols / Noto Sans Symbols 2** -- the source of the glyphs in
  the generated `assets/fonts/g9-symbols.ttf` supplement; SIL Open Font
  License 1.1.
- **gen1recomp** (<https://github.com/bryanthaboi/gen1recomp>) -- the engine this
  project builds on; its public mod API and engine behaviour are what this code
  hooks. See that repository for its own licence.
