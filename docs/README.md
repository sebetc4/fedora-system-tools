# Fedora System Tools Documentation

The current state of fedora-system-tools: its shared conventions and mechanisms, the API of the
shared library, and what each module does and how it is configured. Installation and the command
reference stay in the repository's `README.md`; the roadmaps, which plan and record the work,
keep their own folder.

## Documents

- [Core](core/README.md) — conventions, versioning, `setup.sh`, log rotation and installed paths; read before changing a script or an installer.
- [Shared Library](lib/README.md) — the API of each `lib/` file; read before using or changing a library function.
- [Modules](modules/README.md) — what each module does, how it installs and how it is configured; read before working on a module.
- [Roadmaps](roadmap/README.md) — the open and completed roadmaps and their order; read to know what work is planned or under way.

## Rules

- The documents hold the current state, by domain. A settled decision goes into its
  domain's document, under Decisions; a question under discussion stays an untracked note
  under `notes/<domain>/`, which no document cites.
- A document changes in the commit of the change it describes.
- Links lead to the current state only: never to a code line, a file not yet written or a
  note.
- Every folder holding documents has a README listing each document and subfolder, one
  line each.
