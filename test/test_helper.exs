# Issue ids are small integers, so a list of them is a valid charlist and
# ExUnit renders [101, 100, 99] as ~c"edc" — unreadable in a failure diff.
ExUnit.configure(inspect_opts: [charlists: :as_lists])
ExUnit.start()
