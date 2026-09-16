# Changelog

## [3.5.2](https://github.com/udondan/reminders-cli/compare/v3.5.1...v3.5.2) (2026-09-16)


### Bug Fixes

* point the timeIsSignificant warning at this project's issue tracker ([#90](https://github.com/udondan/reminders-cli/issues/90)) ([fc6e263](https://github.com/udondan/reminders-cli/commit/fc6e2634f957105a1ac810556bcb553fc5e7839b))

## [3.5.1](https://github.com/udondan/reminders-cli/compare/v3.5.0...v3.5.1) (2026-09-16)


### Bug Fixes

* accept values starting with a dash for --notes and --search ([#87](https://github.com/udondan/reminders-cli/issues/87)) ([1af30e1](https://github.com/udondan/reminders-cli/commit/1af30e1ffbb72d8a4961dae131fd95c66d179387)), closes [#86](https://github.com/udondan/reminders-cli/issues/86)

## [3.5.0](https://github.com/udondan/reminders-cli/compare/v3.4.0...v3.5.0) (2026-09-14)


### Features

* accept multiple reminder IDs in complete, uncomplete, postpone, delete and edit ([#75](https://github.com/udondan/reminders-cli/issues/75)) ([bfa08f2](https://github.com/udondan/reminders-cli/commit/bfa08f2119405b228ab4912d1fdbe7f9187d5cb1)), closes [#72](https://github.com/udondan/reminders-cli/issues/72)
* add local-time dates and isAllDay to JSON output ([#79](https://github.com/udondan/reminders-cli/issues/79)) ([1f06100](https://github.com/udondan/reminders-cli/commit/1f061009ddd9b8606885850b4f5d0d77669f19b7)), closes [#74](https://github.com/udondan/reminders-cli/issues/74)


### Bug Fixes

* don't request Reminders access for the help subcommand ([550f7b6](https://github.com/udondan/reminders-cli/commit/550f7b66a6b43f6803f9e90ac6d95e9220f81e9e))
* name the existing --include-completed flag in the show and show-all conflict error ([550f7b6](https://github.com/udondan/reminders-cli/commit/550f7b66a6b43f6803f9e90ac6d95e9220f81e9e))

## [3.4.0](https://github.com/udondan/reminders-cli/compare/v3.3.0...v3.4.0) (2026-09-14)


### Features

* add --repeat-on weekday selectors for weekly repeats ([#67](https://github.com/udondan/reminders-cli/issues/67)) ([b86cd23](https://github.com/udondan/reminders-cli/commit/b86cd2397038f73948eee20871a844bb9aea828f))
* add delete-list subcommand with --confirm guard ([#70](https://github.com/udondan/reminders-cli/issues/70)) ([e3c838e](https://github.com/udondan/reminders-cli/commit/e3c838e261a9039f0885ac2b582003b2b03c99b7)), closes [#50](https://github.com/udondan/reminders-cli/issues/50)
* add doctor subcommand for permission and environment diagnostics ([#69](https://github.com/udondan/reminders-cli/issues/69)) ([6738316](https://github.com/udondan/reminders-cli/commit/673831665189ac8f1d14533f0e6740ad1a0d6a59)), closes [#52](https://github.com/udondan/reminders-cli/issues/52)
* add opt-in pretty output format for reminder listings ([#71](https://github.com/udondan/reminders-cli/issues/71)) ([c91cfc0](https://github.com/udondan/reminders-cli/commit/c91cfc02f8fa0f15877bee387953ca244b7aaf67)), closes [#54](https://github.com/udondan/reminders-cli/issues/54)
* add today, overdue and upcoming subcommands ([#65](https://github.com/udondan/reminders-cli/issues/65)) ([131be42](https://github.com/udondan/reminders-cli/commit/131be42512f7e38573e46ab0bba130d75315c059))
* show and filter by flagged status ([#64](https://github.com/udondan/reminders-cli/issues/64)) ([31c233d](https://github.com/udondan/reminders-cli/commit/31c233d6d0c52710c0eb0474b43ce421dcf3c2f6)), closes [#51](https://github.com/udondan/reminders-cli/issues/51)
* show open and overdue reminder counts in show-lists ([#60](https://github.com/udondan/reminders-cli/issues/60)) ([50dd6c8](https://github.com/udondan/reminders-cli/commit/50dd6c8e990bc1868b4422818f5ccf95b6e1ba0c)), closes [#48](https://github.com/udondan/reminders-cli/issues/48)


### Bug Fixes

* apply --repeat rule when adding a reminder ([#66](https://github.com/udondan/reminders-cli/issues/66)) ([aa806a4](https://github.com/udondan/reminders-cli/commit/aa806a497c2806c3ab5e4268bdec1079d5047728))
* omit nextDueDate for completed reminders ([#68](https://github.com/udondan/reminders-cli/issues/68)) ([3059841](https://github.com/udondan/reminders-cli/commit/305984167ae2af12a0a04f697e56708c70f4fcba))

## [3.3.0](https://github.com/udondan/reminders-cli/compare/v3.2.0...v3.3.0) (2026-09-13)


### Features

* match list names loosely and accept reminder ID prefixes ([#57](https://github.com/udondan/reminders-cli/issues/57)) ([b191fbb](https://github.com/udondan/reminders-cli/commit/b191fbb54b6199ff5e9a7b63fd211d031edc231c)), closes [#46](https://github.com/udondan/reminders-cli/issues/46)

## [3.2.0](https://github.com/udondan/reminders-cli/compare/v3.1.1...v3.2.0) (2026-09-13)


### Features

* report errors as structured messages on stderr ([#55](https://github.com/udondan/reminders-cli/issues/55)) ([dca2cb6](https://github.com/udondan/reminders-cli/commit/dca2cb6dfb81ad2fc83bc8b7022bf41621015dea)), closes [#45](https://github.com/udondan/reminders-cli/issues/45)

## [3.1.1](https://github.com/udondan/reminders-cli/compare/v3.1.0...v3.1.1) (2026-09-13)


### Miscellaneous Chores

* publish releases as drafts so the tarball can be attached before publishing ([#40](https://github.com/udondan/reminders-cli/issues/40)) ([740fcfe](https://github.com/udondan/reminders-cli/commit/740fcfe2c65c18dedd95e75e4fce94bfeb476809))

## [3.1.0](https://github.com/udondan/reminders-cli/compare/v3.0.1...v3.1.0) (2026-09-13)


### Features

* add --clear-notes to edit ([46c8212](https://github.com/udondan/reminders-cli/commit/46c8212072c1b51ab6a2bb8441a285501e71f8e7))
* add --default-only option to show-lists ([7958274](https://github.com/udondan/reminders-cli/commit/7958274124c74b8282738b38ccd54e6c04f7ff04))
* make show-lists --default-only honor --format and print the list id ([a90b2a0](https://github.com/udondan/reminders-cli/commit/a90b2a0ddce4be5fc0c31a237e9bcedc6662c2bd))


### Bug Fixes

* count relative due dates by calendar day ([c655a7d](https://github.com/udondan/reminders-cli/commit/c655a7ddb66c34cb09a821324fad69a266faaaed))
* only consider reminder-capable sources in new-list ([045e468](https://github.com/udondan/reminders-cli/commit/045e468f65360291e21007802fb8b9acb8be95a2))

## [3.0.1](https://github.com/udondan/reminders-cli/compare/v3.0.0...v3.0.1) (2026-09-13)


### ⚠ BREAKING CHANGES

* complete, uncomplete, edit, postpone, and delete no longer accept a numeric position (e.g. `reminders complete List 0`). Pass the reminder's ID instead, as shown by `show`/`show-all`.

### Features

* add --list option to move a reminder to a different list ([ee04a0f](https://github.com/udondan/reminders-cli/commit/ee04a0fa38752ea389a380cfba7437a8cfa22785))
* add --priority and --clear-priority options to edit command ([ffddc22](https://github.com/udondan/reminders-cli/commit/ffddc228dd8bb045af3cead4ccc8274525fdd545))
* add --repeat recurrence support for add/edit ([66315fd](https://github.com/udondan/reminders-cli/commit/66315fdb5d0c4931f4097c68774e26d8eb0246de))
* add edit --priority and edit --list options ([50c1ca7](https://github.com/udondan/reminders-cli/commit/50c1ca7f021047fd365c50c7b39759501eb3cde5))
* add filter flags to show and show-all ([#6](https://github.com/udondan/reminders-cli/issues/6)) ([f60c49e](https://github.com/udondan/reminders-cli/commit/f60c49e8fb168af3bf2a0c65ed41ff5f63b647d6))
* add hasRecurrence flag and computed nextDueDate to JSON output ([de37149](https://github.com/udondan/reminders-cli/commit/de3714901dd653ac3d19bc7ea2b5dfd5f7f34309))
* add postpone command to move due dates without changing repeat rules ([#11](https://github.com/udondan/reminders-cli/issues/11)) ([82ec3bc](https://github.com/udondan/reminders-cli/commit/82ec3bc21f70ca8257ebc4e857b117c391ff66ce))
* add sort support to show-all, add priority sort value ([#8](https://github.com/udondan/reminders-cli/issues/8)) ([065bcd9](https://github.com/udondan/reminders-cli/commit/065bcd955fc3b512b0bd524fbe234d35b8465b3b))
* allow editing recurrence end date without discarding the rule ([6305162](https://github.com/udondan/reminders-cli/commit/6305162d51fa16e69dd3f3134168251368069c5a))
* Bring in list IDs and delete-completed-item support from upstream ([#7](https://github.com/udondan/reminders-cli/issues/7)) ([c843a7e](https://github.com/udondan/reminders-cli/commit/c843a7e11c7aa25b6a62e3374170b81173ee5328))
* preserve calendar metadata on end-only recurrence edits ([ead7168](https://github.com/udondan/reminders-cli/commit/ead7168daaa2ed57a2db3c8addaa6aba87538647))
* remove positional-index lookup for reminder items, ID-only ([#12](https://github.com/udondan/reminders-cli/issues/12)) ([c3138a4](https://github.com/udondan/reminders-cli/commit/c3138a4c0374134508274c6e06f77afefe43f312))
* Report completionDate as null and add --completed-since filter ([#9](https://github.com/udondan/reminders-cli/issues/9)) ([8188e19](https://github.com/udondan/reminders-cli/commit/8188e19eb15016e4a589d61ce21fa5b26a97364c))


### Bug Fixes

* don't request Reminders access for commands that don't need it ([#22](https://github.com/udondan/reminders-cli/issues/22)) ([7dada8f](https://github.com/udondan/reminders-cli/commit/7dada8fd8d3bd364eaef6666f3e53944e799b1b7))
* filter natural-language date components consistently ([286b82e](https://github.com/udondan/reminders-cli/commit/286b82e02fda3421b2596905b456e7f8406c849a))
* filter natural-language date components consistently ([3d2f60f](https://github.com/udondan/reminders-cli/commit/3d2f60f05789f3c80c57133544fdda0e331a8fde))

## [3.0.0](https://github.com/udondan/reminders-cli/compare/v2.5.1...v3.0.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* complete, uncomplete, edit, postpone, and delete no longer accept a numeric position (e.g. `reminders complete List 0`). Pass the reminder's ID instead, as shown by `show`/`show-all`.

### Features

* add --list option to move a reminder to a different list ([ee04a0f](https://github.com/udondan/reminders-cli/commit/ee04a0fa38752ea389a380cfba7437a8cfa22785))
* add --priority and --clear-priority options to edit command ([ffddc22](https://github.com/udondan/reminders-cli/commit/ffddc228dd8bb045af3cead4ccc8274525fdd545))
* add --repeat recurrence support for add/edit ([66315fd](https://github.com/udondan/reminders-cli/commit/66315fdb5d0c4931f4097c68774e26d8eb0246de))
* add edit --priority and edit --list options ([50c1ca7](https://github.com/udondan/reminders-cli/commit/50c1ca7f021047fd365c50c7b39759501eb3cde5))
* add filter flags to show and show-all ([#6](https://github.com/udondan/reminders-cli/issues/6)) ([f60c49e](https://github.com/udondan/reminders-cli/commit/f60c49e8fb168af3bf2a0c65ed41ff5f63b647d6))
* add hasRecurrence flag and computed nextDueDate to JSON output ([de37149](https://github.com/udondan/reminders-cli/commit/de3714901dd653ac3d19bc7ea2b5dfd5f7f34309))
* add postpone command to move due dates without changing repeat rules ([#11](https://github.com/udondan/reminders-cli/issues/11)) ([82ec3bc](https://github.com/udondan/reminders-cli/commit/82ec3bc21f70ca8257ebc4e857b117c391ff66ce))
* add sort support to show-all, add priority sort value ([#8](https://github.com/udondan/reminders-cli/issues/8)) ([065bcd9](https://github.com/udondan/reminders-cli/commit/065bcd955fc3b512b0bd524fbe234d35b8465b3b))
* allow editing recurrence end date without discarding the rule ([6305162](https://github.com/udondan/reminders-cli/commit/6305162d51fa16e69dd3f3134168251368069c5a))
* Bring in list IDs and delete-completed-item support from upstream ([#7](https://github.com/udondan/reminders-cli/issues/7)) ([c843a7e](https://github.com/udondan/reminders-cli/commit/c843a7e11c7aa25b6a62e3374170b81173ee5328))
* preserve calendar metadata on end-only recurrence edits ([ead7168](https://github.com/udondan/reminders-cli/commit/ead7168daaa2ed57a2db3c8addaa6aba87538647))
* remove positional-index lookup for reminder items, ID-only ([#12](https://github.com/udondan/reminders-cli/issues/12)) ([c3138a4](https://github.com/udondan/reminders-cli/commit/c3138a4c0374134508274c6e06f77afefe43f312))
* Report completionDate as null and add --completed-since filter ([#9](https://github.com/udondan/reminders-cli/issues/9)) ([8188e19](https://github.com/udondan/reminders-cli/commit/8188e19eb15016e4a589d61ce21fa5b26a97364c))


### Bug Fixes

* don't request Reminders access for commands that don't need it ([#22](https://github.com/udondan/reminders-cli/issues/22)) ([7dada8f](https://github.com/udondan/reminders-cli/commit/7dada8fd8d3bd364eaef6666f3e53944e799b1b7))
* filter natural-language date components consistently ([286b82e](https://github.com/udondan/reminders-cli/commit/286b82e02fda3421b2596905b456e7f8406c849a))
* filter natural-language date components consistently ([3d2f60f](https://github.com/udondan/reminders-cli/commit/3d2f60f05789f3c80c57133544fdda0e331a8fde))

## [3.0.0](https://github.com/udondan/reminders-cli/compare/46896d1...v3.0.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* complete, uncomplete, edit, postpone, and delete no longer accept a numeric position (e.g. `reminders complete List 0`). Pass the reminder's ID instead, as shown by `show`/`show-all`.

### Features

* add --list option to move a reminder to a different list ([ee04a0f](https://github.com/udondan/reminders-cli/commit/ee04a0fa38752ea389a380cfba7437a8cfa22785))
* add --priority and --clear-priority options to edit command ([ffddc22](https://github.com/udondan/reminders-cli/commit/ffddc228dd8bb045af3cead4ccc8274525fdd545))
* add --repeat recurrence support for add/edit ([66315fd](https://github.com/udondan/reminders-cli/commit/66315fdb5d0c4931f4097c68774e26d8eb0246de))
* add filter flags to show and show-all ([#6](https://github.com/udondan/reminders-cli/issues/6)) ([f60c49e](https://github.com/udondan/reminders-cli/commit/f60c49e8fb168af3bf2a0c65ed41ff5f63b647d6))
* add hasRecurrence flag and computed nextDueDate to JSON output ([de37149](https://github.com/udondan/reminders-cli/commit/de3714901dd653ac3d19bc7ea2b5dfd5f7f34309))
* add postpone command to move due dates without changing repeat rules ([#11](https://github.com/udondan/reminders-cli/issues/11)) ([82ec3bc](https://github.com/udondan/reminders-cli/commit/82ec3bc21f70ca8257ebc4e857b117c391ff66ce))
* add sort support to show-all, add priority sort value ([#8](https://github.com/udondan/reminders-cli/issues/8)) ([065bcd9](https://github.com/udondan/reminders-cli/commit/065bcd955fc3b512b0bd524fbe234d35b8465b3b))
* allow editing recurrence end date without discarding the rule ([6305162](https://github.com/udondan/reminders-cli/commit/6305162d51fa16e69dd3f3134168251368069c5a))
* Bring in list IDs and delete-completed-item support from upstream ([#7](https://github.com/udondan/reminders-cli/issues/7)) ([c843a7e](https://github.com/udondan/reminders-cli/commit/c843a7e11c7aa25b6a62e3374170b81173ee5328))
* preserve calendar metadata on end-only recurrence edits ([ead7168](https://github.com/udondan/reminders-cli/commit/ead7168daaa2ed57a2db3c8addaa6aba87538647))
* remove positional-index lookup for reminder items, ID-only ([#12](https://github.com/udondan/reminders-cli/issues/12)) ([c3138a4](https://github.com/udondan/reminders-cli/commit/c3138a4c0374134508274c6e06f77afefe43f312))
* Report completionDate as null and add --completed-since filter ([#9](https://github.com/udondan/reminders-cli/issues/9)) ([8188e19](https://github.com/udondan/reminders-cli/commit/8188e19eb15016e4a589d61ce21fa5b26a97364c))


### Bug Fixes

* filter natural-language date components consistently ([3d2f60f](https://github.com/udondan/reminders-cli/commit/3d2f60f05789f3c80c57133544fdda0e331a8fde))
