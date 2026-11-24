# 3D visual fidelity and basketball authenticity overhaul (D-072)

Plan, audit and recommendation: [../../plans/3D_FIDELITY_PLAN.md](../../plans/3D_FIDELITY_PLAN.md). Decision: D-072 in `docs/DECISIONS.md`. Pictures for every milestone are in the `m0` to `m6` folders next to these documents.

| Milestone | What | Report |
|---|---|---|
| M0 | Audit, recommendation, showcase tool, baseline pictures | the plan above, `m0/` |
| M1 | Skinned characters: archetypes, skeleton, head, hair, uniform | [M1_CHARACTER_V2.md](M1_CHARACTER_V2.md) |
| M2 | 27 animation states, ground contact, two-hand ball IK, event actions, the double-advance fix | [M2_ANIMATION.md](M2_ANIMATION.md) |
| M3 | Real-size ball, shader hardwood court, hoop and net | [M3_BALL_COURT_HOOP.md](M3_BALL_COURT_HOOP.md) |
| M4 | Drawn crowd, seating, banners, truss, scorer table, courtside, bench, referees, coaches | [M4_ARENA.md](M4_ARENA.md) |
| M5 | Front close shots, 3D introductions, celebrations, lower main camera | [M5_BROADCAST_INTEGRATION.md](M5_BROADCAST_INTEGRATION.md) |
| M6 | Scaling benchmarks, soak, leak, determinism, modes, phone fallback | [M6_VALIDATION.md](M6_VALIDATION.md) |

## Verdict (honest)
The 3D view now shows recognisable, differently built players in real uniforms, moving through 29 basketball states, on a court, a hoop and in an arena with real proportions, and it passes every pre-registered limit on the development machine with the full test suites green. It is stylised realism made entirely in code. It is **not** hand-modelled or motion-captured, faces read only at showcase distance (the 28 ft rule of D-070 keeps the broadcast camera back), fingers are rigid, the ball is not a physics simulation, the spectators in the crowd are painted cards, and nothing was measured on weaker hardware. The next step towards a higher ceiling is a Blender and glTF production pipeline, which the stable bone and surface names were designed for.
