defmodule Bee.Query.Cursor do
  @moduledoc false

  # Keyset pagination cursor (GC-5834). A cursor names the last row of a page by the
  # values of the spec's `order_by` columns, so the next page is "rows strictly after
  # this one" in the same order. Unlike an offset, that stays stable while issues are
  # created or closed between pages: offset paging duplicated rows under exactly that
  # churn.
  #
  # The encoding is base64url JSON of `%{"o" => order_by, "v" => values}`. It is
  # opaque to callers but not secret; a well-formed edited cursor only moves the page
  # boundary of a read. Decoding checks the shape, that the cursor was minted for the
  # same `order_by`, and each value's type, and rejects anything else with
  # `{:invalid_cursor, cursor}`.

  @spec encode(keyword(:asc | :desc), map()) :: String.t()
  def encode(order_by, row) do
    %{
      "o" => Enum.map(order_by, fn {column, direction} -> [column, direction] end),
      "v" => Enum.map(order_by, fn {column, _direction} -> Map.fetch!(row, column) end)
    }
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(term(), keyword(:asc | :desc)) ::
          {:ok, [{atom(), :asc | :desc, term()}]} | {:error, {:invalid_cursor, term()}}
  def decode(cursor, order_by) when is_binary(cursor) do
    expected =
      Enum.map(order_by, fn {column, direction} -> [to_string(column), to_string(direction)] end)

    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"o" => ^expected, "v" => values}} when is_list(values) <- Jason.decode(json),
         true <- length(values) == length(order_by),
         keyed = Enum.zip_with(order_by, values, fn {c, d}, v -> {c, d, v} end),
         true <- Enum.all?(keyed, &valid_value?/1) do
      {:ok, keyed}
    else
      _ -> {:error, {:invalid_cursor, cursor}}
    end
  end

  def decode(cursor, _order_by), do: {:error, {:invalid_cursor, cursor}}

  defp valid_value?({column, _direction, value}) when column in [:created_at, :updated_at],
    do: is_binary(value)

  defp valid_value?({:priority, _direction, value}), do: is_nil(value) or is_integer(value)
  defp valid_value?({:id, _direction, value}), do: is_binary(value) and value != ""
  defp valid_value?(_), do: false
end
