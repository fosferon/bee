defmodule Bee.Dependency.TypeTest do
  use ExUnit.Case, async: true

  alias Bee.Dependency.Type

  test "dependency vocabulary has seven meaningful members" do
    assert length(Type.all()) == 7
    assert Type.gating() == [:blocks, :waits_for, :conditional_blocks]
  end

  test "write validation distinguishes unknown and projected types" do
    assert :ok = Type.validate(:related)
    assert {:error, :unwritable_dep_type} = Type.validate(:parent_child)
    assert {:error, :unknown_dep_type} = Type.validate(:invented)
  end
end
