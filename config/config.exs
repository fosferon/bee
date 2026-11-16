import Config

# Compiles the test-only fault injection and export observer in `Bee.TestSeam` into
# bee's own test build. Configuration is not shipped with the package, and a
# dependency's config is never loaded by its parent, so no other build has it.
if config_env() == :test do
  config :bee, test_faults: true
end
