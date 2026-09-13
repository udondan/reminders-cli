# Changelog

## [3.0.0](https://github.com/udondan/reminders-cli/compare/v2.5.1...v3.0.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* complete, uncomplete, edit, postpone, and delete no longer accept a numeric position (e.g. `reminders complete List 0`). Pass the reminder's ID instead, as shown by `show`/`show-all`.

### Features

* Add --due-date and --clear-due-date to the edit command ([#108](https://github.com/udondan/reminders-cli/issues/108)) ([46896d1](https://github.com/udondan/reminders-cli/commit/46896d1ddd989258d9b6b04a1072578548fc13ff))
* Add --due-date to show ([#40](https://github.com/udondan/reminders-cli/issues/40)) ([74e0b80](https://github.com/udondan/reminders-cli/commit/74e0b804ef4fac03b39069d76a5c3c1bb5a93101))
* Add --include-overdue arg to include items before the specified due date ([#98](https://github.com/udondan/reminders-cli/issues/98)) ([f37419a](https://github.com/udondan/reminders-cli/commit/f37419a42c47e770f8482bb9363b7b92f4eefb52))
* add --list option to move a reminder to a different list ([ee04a0f](https://github.com/udondan/reminders-cli/commit/ee04a0fa38752ea389a380cfba7437a8cfa22785))
* Add --notes option to edit command ([#62](https://github.com/udondan/reminders-cli/issues/62)) ([43be048](https://github.com/udondan/reminders-cli/commit/43be048649819bc749be16f443f9e159e2d6c926))
* Add --notes when adding reminders ([#56](https://github.com/udondan/reminders-cli/issues/56)) ([39dd160](https://github.com/udondan/reminders-cli/commit/39dd160341250953c14b38f9571cccb85526322b))
* add --priority and --clear-priority options to edit command ([ffddc22](https://github.com/udondan/reminders-cli/commit/ffddc228dd8bb045af3cead4ccc8274525fdd545))
* Add --priority to reminder adding ([#42](https://github.com/udondan/reminders-cli/issues/42)) ([a880d5b](https://github.com/udondan/reminders-cli/commit/a880d5b0c60f17acf0a8b87d9031599566b57028))
* add --repeat recurrence support for add/edit ([66315fd](https://github.com/udondan/reminders-cli/commit/66315fdb5d0c4931f4097c68774e26d8eb0246de))
* Add alarms for notifications with due dates ([#77](https://github.com/udondan/reminders-cli/issues/77)) ([bcddf38](https://github.com/udondan/reminders-cli/commit/bcddf38790c8f0d6b71133658502224ff4fc28cc))
* Add completion for reminders list names ([#46](https://github.com/udondan/reminders-cli/issues/46)) ([160d58c](https://github.com/udondan/reminders-cli/commit/160d58c21e243f91680f354252a534f1845a81eb))
* Add delete reminder command ([#43](https://github.com/udondan/reminders-cli/issues/43)) ([6030c1a](https://github.com/udondan/reminders-cli/commit/6030c1ad5c14463b0f01e6fcf7edee976d14cdb0))
* Add due date setting ([#20](https://github.com/udondan/reminders-cli/issues/20)) ([f9c0926](https://github.com/udondan/reminders-cli/commit/f9c09265d3e8be8670986a68390988853ad0a362))
* add edit --priority and edit --list options ([50c1ca7](https://github.com/udondan/reminders-cli/commit/50c1ca7f021047fd365c50c7b39759501eb3cde5))
* Add edit command ([#45](https://github.com/udondan/reminders-cli/issues/45)) ([0ca4730](https://github.com/udondan/reminders-cli/commit/0ca4730886119a3428841c6b67abc2f3f5ce9079))
* add filter flags to show and show-all ([#6](https://github.com/udondan/reminders-cli/issues/6)) ([f60c49e](https://github.com/udondan/reminders-cli/commit/f60c49e8fb168af3bf2a0c65ed41ff5f63b647d6))
* Add flags for showing completed reminders ([#41](https://github.com/udondan/reminders-cli/issues/41)) ([bb097d8](https://github.com/udondan/reminders-cli/commit/bb097d8ba4a532334ea20da562a3f4f242bb6241))
* add hasRecurrence flag and computed nextDueDate to JSON output ([de37149](https://github.com/udondan/reminders-cli/commit/de3714901dd653ac3d19bc7ea2b5dfd5f7f34309))
* add json output and expose external identifier ([#55](https://github.com/udondan/reminders-cli/issues/55)) ([941ae77](https://github.com/udondan/reminders-cli/commit/941ae77efb58ebb294e6a391cb56e30292f746f8))
* Add new-list command ([#44](https://github.com/udondan/reminders-cli/issues/44)) ([b9ca1c3](https://github.com/udondan/reminders-cli/commit/b9ca1c382ff607a42bdd989d395f9bdf576955f4))
* add postpone command to move due dates without changing repeat rules ([#11](https://github.com/udondan/reminders-cli/issues/11)) ([82ec3bc](https://github.com/udondan/reminders-cli/commit/82ec3bc21f70ca8257ebc4e857b117c391ff66ce))
* Add private API for knowing if time should be used ([#50](https://github.com/udondan/reminders-cli/issues/50)) ([1345c76](https://github.com/udondan/reminders-cli/commit/1345c76070e2ed11dd08a5aa14b8a301eee227c7))
* Add show-all command ([#47](https://github.com/udondan/reminders-cli/issues/47)) ([eed1655](https://github.com/udondan/reminders-cli/commit/eed1655f92a3c6c03e41511d47733a096e554ad1))
* add sort support to show-all, add priority sort value ([#8](https://github.com/udondan/reminders-cli/issues/8)) ([065bcd9](https://github.com/udondan/reminders-cli/commit/065bcd955fc3b512b0bd524fbe234d35b8465b3b))
* Add sorting reminders when showing ([#57](https://github.com/udondan/reminders-cli/issues/57)) ([1391efb](https://github.com/udondan/reminders-cli/commit/1391efbd6b50afc706dff371870ff718c27c45a6))
* Add uncomplete command ([#64](https://github.com/udondan/reminders-cli/issues/64)) ([ba0841a](https://github.com/udondan/reminders-cli/commit/ba0841a73166cba3752cc80fbc53930c19f99fdf))
* Add zsh completions ([794aa1b](https://github.com/udondan/reminders-cli/commit/794aa1b36221a37a4b99e84ce6ca0bb10bcb6879))
* allow editing recurrence end date without discarding the rule ([6305162](https://github.com/udondan/reminders-cli/commit/6305162d51fa16e69dd3f3134168251368069c5a))
* Bring in list IDs and delete-completed-item support from upstream ([#7](https://github.com/udondan/reminders-cli/issues/7)) ([c843a7e](https://github.com/udondan/reminders-cli/commit/c843a7e11c7aa25b6a62e3374170b81173ee5328))
* Emit createdDate and lastModifiedDate in JSON-format output. ([#86](https://github.com/udondan/reminders-cli/issues/86)) ([f94333f](https://github.com/udondan/reminders-cli/commit/f94333f1369ea19f66ccfa3f82fe61fddc7b6f48))
* Improve JSON output and add display options to ShowAll ([#69](https://github.com/udondan/reminders-cli/issues/69)) ([3ab065c](https://github.com/udondan/reminders-cli/commit/3ab065c52b310007532ffb036635d4ca8f66cd69))
* Initial Commit ([fefbd69](https://github.com/udondan/reminders-cli/commit/fefbd694220a95835cbbe1fc8634538e75ef3ea2))
* preserve calendar metadata on end-only recurrence edits ([ead7168](https://github.com/udondan/reminders-cli/commit/ead7168daaa2ed57a2db3c8addaa6aba87538647))
* Print due dates beside reminders ([#16](https://github.com/udondan/reminders-cli/issues/16)) ([665caab](https://github.com/udondan/reminders-cli/commit/665caabbbc065ab1f8805f25054c94fae083d9c3))
* remove positional-index lookup for reminder items, ID-only ([#12](https://github.com/udondan/reminders-cli/issues/12)) ([c3138a4](https://github.com/udondan/reminders-cli/commit/c3138a4c0374134508274c6e06f77afefe43f312))
* Report completionDate as null and add --completed-since filter ([#9](https://github.com/udondan/reminders-cli/issues/9)) ([8188e19](https://github.com/udondan/reminders-cli/commit/8188e19eb15016e4a589d61ce21fa5b26a97364c))


### Bug Fixes

* allow deleting a reminder by external id after it's been completed ([#106](https://github.com/udondan/reminders-cli/issues/106)) ([dfc7776](https://github.com/udondan/reminders-cli/commit/dfc7776c6a9b3b9734773def08e9aa41cf8aa1ef))
* Display reminders in the same order as they appear in the UI ([#11](https://github.com/udondan/reminders-cli/issues/11)) ([d2cad3e](https://github.com/udondan/reminders-cli/commit/d2cad3e9c127b739c193fea7309df850b2b32f73))
* Don't add alarm for dates without times ([#81](https://github.com/udondan/reminders-cli/issues/81)) ([5f75533](https://github.com/udondan/reminders-cli/commit/5f75533dfd07c30c5251f188de6a9841d5d1a928))
* filter natural-language date components consistently ([286b82e](https://github.com/udondan/reminders-cli/commit/286b82e02fda3421b2596905b456e7f8406c849a))
* filter natural-language date components consistently ([3d2f60f](https://github.com/udondan/reminders-cli/commit/3d2f60f05789f3c80c57133544fdda0e331a8fde))
* Fix permissions on macOS Sonoma ([#70](https://github.com/udondan/reminders-cli/issues/70)) ([9b4593c](https://github.com/udondan/reminders-cli/commit/9b4593c3c4bdeb5f00cbedb740b1693615a7ba54))
* Fix taking remaining contents as reminder ([#21](https://github.com/udondan/reminders-cli/issues/21)) ([9eadd38](https://github.com/udondan/reminders-cli/commit/9eadd38f22a9bf6b352adcfa20427884b342e0ba))
* Update successful messages and exit codes ([f631536](https://github.com/udondan/reminders-cli/commit/f63153694f7afeffe67c8d30b46020dac320e268))
