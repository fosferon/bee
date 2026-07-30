defmodule Bee.IdTest do
  use ExUnit.Case, async: true

  alias Bee.Id

  describe "parse/1" do
    test "parses a prefixed string to its integer form" do
      assert {:ok, 805} = Id.parse("app-805")
    end

    test "accepts an already-integer id idempotently" do
      assert {:ok, 805} = Id.parse(805)
    end

    test "rejects a prefix-only id (no number)" do
      assert {:error, :invalid_id} = Id.parse("app-")
    end

    test "rejects nil" do
      assert {:error, :invalid_id} = Id.parse(nil)
    end

    test "rejects an empty string" do
      assert {:error, :invalid_id} = Id.parse("")
    end

    test "rejects a non-numeric suffix" do
      assert {:error, :invalid_id} = Id.parse("app-abc")
    end

    test "rejects a bare string without prefix" do
      assert {:error, :invalid_id} = Id.parse("805")
    end

    test "rejects a string with trailing garbage after number" do
      assert {:error, :invalid_id} = Id.parse("app-805x")
    end
  end

  describe "parse!/1" do
    test "returns the integer for a valid prefixed id" do
      assert 805 = Id.parse!("app-805")
    end

    test "returns the integer for an already-integer id" do
      assert 805 = Id.parse!(805)
    end

    test "raises ArgumentError for a prefix-only id" do
      assert_raise ArgumentError, ~r/invalid id/, fn -> Id.parse!("app-") end
    end

    test "raises ArgumentError for nil" do
      assert_raise ArgumentError, ~r/invalid id/, fn -> Id.parse!(nil) end
    end

    test "raises ArgumentError for an empty string" do
      assert_raise ArgumentError, ~r/invalid id/, fn -> Id.parse!("") end
    end
  end

  describe "to_prefixed/2" do
    test "converts an integer to a prefixed string" do
      assert "app-805" = Id.to_prefixed(805, "app")
    end

    test "passes through an already-prefixed string idempotently" do
      assert "app-805" = Id.to_prefixed("app-805", "app")
    end

    test "converts a bare number string to a prefixed string" do
      assert "app-805" = Id.to_prefixed("805", "app")
    end

    test "passes through a free-form string id (with hyphen)" do
      assert "bee-legacy" = Id.to_prefixed("bee-legacy", "app")
    end

    test "raises ArgumentError for nil" do
      assert_raise ArgumentError, fn -> Id.to_prefixed(nil, "app") end
    end

    test "raises ArgumentError for an empty string" do
      assert_raise ArgumentError, fn -> Id.to_prefixed("", "app") end
    end

    test "raises ArgumentError for a non-numeric bare string" do
      assert_raise ArgumentError, fn -> Id.to_prefixed("abc", "app") end
    end
  end

  describe "format_parent/2" do
    test "returns nil for nil parent" do
      assert Id.format_parent(nil, "app") == nil
    end

    test "returns nil for empty string parent" do
      assert Id.format_parent("", "app") == nil
    end

    test "converts an integer parent to a prefixed string" do
      assert "app-5" = Id.format_parent(5, "app")
    end

    test "passes through an already-prefixed parent" do
      assert "app-5" = Id.format_parent("app-5", "app")
    end

    test "converts a bare number string parent" do
      assert "app-5" = Id.format_parent("5", "app")
    end
  end
end
