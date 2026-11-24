# Third Eye Decalcified Co-op

Split-screen two-player co-op for **Destroy All Humans! (2020)** on PC, with an overhauled PK,
a mind & weapons wheel, new mind powers and an in-game trainer.

**Early access:** this is a work in progress. It is not bug-free; known issues are listed in the
trainer's *Known issues* page and in the release README. Built for two players; three and four
players are an early test and are not ready yet.

## What's in here

| Folder | What it is |
| --- | --- |
| `mod/ue4ss/Mods/OverkillCoop` | The mod itself: UE4SS Lua scripts, power icons, logo |
| `padrouter` | `proxy.cpp`: a small XInput proxy DLL (`xinput1_3/1_4/9_1_0.dll`) that gives Player 2 its own controller input |
| `.github/workflows` | Builds the DLLs and packages everything (Actions > Run workflow) |

## Install (players)

Download the release zip from the Nexus page or GitHub Releases and copy its contents into
`steamapps\common\Destroy All Humans!\DH\Binaries\Win64\`. Needs UE4SS v3.0.1 (included in the
release zip).

## Build (developers)

The DLLs are built by the GitHub Actions workflow on `windows-2022` with MSVC. To build by hand,
open an x64 Native Tools prompt and follow the same `cl` / `link` steps as the workflow.

## Credits

- Mod by the Third Eye Decalcified Co-op team (design, art and music by the project lead; code written with Claude)
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT)

*Destroy All Humans! is a trademark of THQ Nordic. Fan-made mod, not affiliated with or endorsed
by THQ Nordic or Black Forest Games.*
