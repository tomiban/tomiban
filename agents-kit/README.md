# Kit de agentes para Claude Code

La sesión principal corre en **Sonnet 5.5** y coordina. Delega en cuatro subagentes:

| Agente | Modelo | Qué hace | Herramientas |
| --- | --- | --- | --- |
| `search` | Haiku 5.5 | Mapea el repo: estructura, módulos, puntos de entrada | Solo lectura |
| `grep` | Haiku 5.5 | Encuentra todas las llamadas o usos de algo | Solo lectura |
| `audit` | Haiku 5.5 | Revisa el diff y corre install, tests y typecheck en un **worktree aparte** | Lectura y Bash |
| `advisor` | Opus 5.5 | Revisión final: publicar, publicar con cambios o no publicar | Solo lectura |

## Instalación

Necesitas `bash`, `python3` y `git`. En Windows, usa WSL o copia los archivos a mano (ver más abajo).

### Para todos tus proyectos (instalación local)

```bash
./install.sh --user
```

Escribe en `~/.claude/`:
- `agents/`: los 4 agentes, disponibles en cualquier proyecto.
- `CLAUDE.md`: agrega la sección "Agent workflow", que aplica a todos tus proyectos.
- `settings.json`: pone `"model": "claude-sonnet-5-5"` si no tenías otro modelo, y agrega permisos de solo lectura de git.

En este modo, `audit` detecta los comandos de test de cada proyecto. Busca primero la sección `## Commands` del `CLAUDE.md` del proyecto, y si no está, revisa `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml` o el `Makefile`. La primera vez que corra los tests de cada proyecto, Claude Code te va a pedir permiso.

### Para un repo concreto (compartido con el equipo por git)

```bash
./install.sh /ruta/al/repo
# o con comandos explícitos:
./install.sh /ruta/al/repo --install "pnpm install --frozen-lockfile" --test "pnpm test" --check "pnpm lint"
```

Escribe en el repo:
- `.claude/agents/`: los 4 agentes.
- `.claude/settings.json`: el modelo y los permisos, incluidos los comandos de test detectados.
- `CLAUDE.md`: las secciones "Agent workflow" y "Commands".
- `scripts/claude-flow.sh`: un script para correr el flujo sin interfaz.
- `.gitignore`: agrega `.claude/worktrees/`.

Detecta automáticamente npm, pnpm, yarn, pytest, Go y Cargo.

Puedes usar los dos modos a la vez. Si un agente existe en el proyecto y en `~/.claude`, **gana el del proyecto**.

### Comportamiento del instalador

- Nunca pisa archivos: si un agente ya existe, lo omite. Con `--force` lo reemplaza.
- Agrega la sección del `CLAUDE.md` una sola vez.
- `settings.json` se combina con el que ya tengas. Tus claves se respetan y a la lista `permissions.allow` solo se le agregan reglas.
- Puedes correrlo varias veces sin duplicar nada.

Después de instalar, abre una sesión nueva de Claude Code y comprueba con `/agents` que aparecen los cuatro.

## Uso

En una sesión interactiva no hace falta nada especial. El `CLAUDE.md` le indica a Claude que delegue y que, antes de cerrar, siga estos pasos:
1. Commit.
2. `audit`.
3. `advisor`, con el diff y el informe pegados en el prompt.
4. Aplicar los cambios que pida, y repetir `audit`.

Sin interfaz (`claude -p`), solo en modo proyecto:

```bash
scripts/claude-flow.sh "Agrega rate limiting a POST /api/secrets"
CLAUDE_FLOW_COMMIT=1 scripts/claude-flow.sh "..."   # además permite git add / git commit
```

## Limitaciones conocidas (vistas en pruebas)

- **En `claude -p`, las reglas `allow` de `settings.json` no se aplicaron** a `audit`. Por eso `claude-flow.sh` pasa los mismos permisos con `--allowedTools`, solo para esa corrida.
- **`audit` solo ve commits.** Su worktree es una copia aparte, así que los cambios sin commit no le llegan.
- **Los subagentes no pueden llamar a otros subagentes.** `audit` busca por su cuenta.
- **`advisor` no tiene Bash.** La sesión principal tiene que pasarle el diff dentro del prompt.
- **Los comandos compuestos (`&&`, `;`, `$?`, redirecciones) piden aprobación** aunque cada parte esté permitida. `audit` está instruido para correr un comando por vez.
- **Costo de referencia:** en las pruebas, una ronda completa de `audit` y `advisor` costó entre $0.25 y $0.70. Opus es la parte más cara.
- Claude no siempre delega: la regla del `CLAUDE.md` guía, pero no obliga. Si quieres forzarlo, pídeselo: "usa grep para…".

## Instalación manual

Copia `files/.claude/agents/*.md` a `~/.claude/agents/` (o a `.claude/agents/` del repo). Agrega el contenido de `files/CLAUDE.agents.md` a tu `CLAUDE.md`. En `settings.json`, pon `"model": "claude-sonnet-5-5"`.
