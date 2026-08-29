# barnacle 

A personal macOS app that tracks internship postings from a hand-picked set of companies, surfaces them newest-first, notifies on new ones, and logs applications — including via a global ⌘J overlay that floats over any app.

## Context Files

Read the following to get the full context of the project:

@context/project-overview.md — architecture, tech stack, data model, scrape strategy
@context/ai-interaction.md — communication, workflow, commit, and review rules
@context/current-feature.md — the feature currently being built (maintained manually)

## Commands

```
open Barnacle.xcodeproj                                  # open in Xcode; build & run with ⌘R
xcodebuild -scheme Barnacle -configuration Debug build   # build from the CLI
xcodebuild -scheme Barnacle test                         # run the test suite
swiftlint       
```