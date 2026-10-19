# Notice

Edge is an independent, open-source project (AGPL-3.0, see `LICENSE`; versions up to
commit 1140dac1 were MIT, see `NOTICE`). It
is not affiliated with, sponsored by, or endorsed by WHOOP, Inc. or any of its
trademarks.

No WHOOP source code, binaries, firmware, or copyrighted assets are included
in this repository.

## wger exercise data

`lib/ui2/activity/wger_exercises.g.dart` contains selected fields (names,
aliases, muscles, equipment, categories) from the [wger](https://wger.de)
exercise database, limited to the movements listed in
`tool/wger_weightlifting_selection.dart`. Each entry is available under
CC BY-SA 3.0, CC BY-SA 4.0 or CC0, and each row keeps its source UUID and the
author/license credits of its base data and translations. This data stays under
those licenses, separate from the AGPL-licensed code. Refresh with
`dart run tool/update_wger_exercises.dart`.

## Sleep-stage model training data

The sleep-stage model in `lib/compute/sleep_stage_gbt.g.dart` was trained on
"Motion and heart rate from a wrist-worn wearable and labeled sleep from
polysomnography" (Walch, O., PhysioNet, 2019,
https://doi.org/10.13026/hmhs-py35), licensed under the Open Data Commons
Attribution License v1.0. Original publication: Walch O, Huang Y, Forger D,
Goldstein C. Sleep stage prediction with raw acceleration and
photoplethysmography heart rate data derived from a consumer wearable device.
Sleep 2019;42(12):zsz180. https://doi.org/10.1093/sleep/zsz180. PhysioNet:
Goldberger AL et al., Circulation 2000;101(23):e215–e220.
