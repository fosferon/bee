defmodule Bee.Query.Interpreter do
  @moduledoc false

  alias Bee.Query.{Cursor, Spec}
  alias Bee.Store.Tree

  @type result :: %{
          issues: [map()],
          withheld: map(),
          refine: keyword(),
          total: non_neg_integer(),
          next: String.t() | nil
        }

  @doc """
  Runs a validated spec on `conn`. `prefix` resolves a bare numeric `under`.

  One page query and one total (the same WHERE, one `COUNT(*)`), then at most one
  recursive CTE each for `keep_ancestors`/`path` and for `fold`, over the page's ids.
  """
  @spec execute(Exqlite.Sqlite3.db(), Spec.t(), String.t() | nil) ::
          {:ok, result()} | {:error, term()}
  def execute(conn, %Spec{} = spec, prefix \\ nil) do
    with {:ok, opts} <- Bee.Store.resolve_under(conn, Spec.to_opts(spec), prefix),
         {:ok, keyset} <- decode_after(spec) do
      {:ok, %{rows: rows, more?: more?}} = Bee.Store.query_page(conn, opts, keyset)
      {:ok, counts} = Bee.Store.query_total(conn, opts, keyset)

      next = if more?, do: Cursor.encode(spec.order_by, List.last(rows))

      chains =
        if spec.path or spec.keep_ancestors,
          do: Tree.ancestor_chains(conn, Enum.map(rows, & &1.id)),
          else: %{}

      context = context_rows(conn, spec, rows, chains)

      chains =
        if spec.path and context != [],
          do: Map.merge(chains, Tree.ancestor_chains(conn, Enum.map(context, & &1.id))),
          else: chains

      all_rows = context ++ rows
      rollups = if spec.fold, do: Tree.rollups(conn, Enum.map(all_rows, & &1.id)), else: %{}

      issues =
        all_rows
        |> Enum.map(&attach_path(&1, spec, chains))
        |> Enum.map(&attach_rollup(&1, spec, rollups))
        |> then(&Bee.Store.enrich(conn, &1, opts))

      {withheld, refine} = Bee.Query.Withheld.build(spec, rows, counts, next)

      {issues, transformed} =
        issues
        |> Bee.Query.Projection.project(spec)
        |> Enum.map(&Bee.Query.Transform.apply(&1, spec.transforms))
        |> Enum.unzip()

      transformed = Enum.reject(transformed, &(&1 == %{}))

      withheld =
        if transformed == [], do: withheld, else: Map.put(withheld, :transformed, transformed)

      refine = if transformed == [], do: refine, else: refine ++ [transforms: %{}]

      {:ok,
       %{issues: issues, withheld: withheld, refine: refine, total: counts.total, next: next}}
    end
  end

  defp decode_after(%Spec{after: nil}), do: {:ok, nil}

  defp decode_after(%Spec{after: cursor, order_by: order_by}),
    do: Cursor.decode(cursor, order_by)

  # keep_ancestors: every match brings its ancestors, marked `context: true`, up to
  # the top of its view. With `under` that top is `under`'s child (or `under` itself
  # with `include_root`); with only `depth` it is the match's depth-0 ancestor; with
  # neither it is the tree's root. An ancestor that is itself a match on this page
  # stays a match. Context rows precede the matches, shallowest first, so a consumer
  # building a tree always meets a parent before its children.
  defp context_rows(_conn, %Spec{keep_ancestors: false}, _rows, _chains), do: []

  defp context_rows(conn, spec, rows, chains) do
    matched = MapSet.new(rows, & &1.id)
    floor = if spec.under && !spec.include_root, do: 1, else: 0

    # ancestor id => {depth to report (nil without a scope), absolute depth}
    wanted =
      Enum.reduce(rows, %{}, fn row, acc ->
        chain = Map.get(chains, row.id, [])

        chain
        |> Enum.filter(&(is_nil(row[:depth]) or row.depth - &1.dist >= floor))
        |> Enum.reject(&MapSet.member?(matched, &1.id))
        |> Enum.reduce(acc, fn ancestor, acc ->
          depth = if row[:depth], do: row.depth - ancestor.dist
          Map.put_new(acc, ancestor.id, {depth, length(chain) - ancestor.dist})
        end)
      end)

    conn
    |> Bee.Store.get_raw_issues(Map.keys(wanted))
    |> Enum.map(fn row ->
      {depth, absolute} = Map.fetch!(wanted, row.id)

      row
      |> Map.put(:context, true)
      |> maybe_put_depth(depth)
      |> then(&{absolute, &1})
    end)
    |> Enum.sort_by(fn {absolute, row} -> {absolute, id_order(row.id)} end)
    |> Enum.map(&elem(&1, 1))
  end

  defp id_order(id) do
    case Bee.Id.parse(id) do
      {:ok, n} -> {n, id}
      {:error, :invalid_id} -> {0, id}
    end
  end

  defp maybe_put_depth(row, nil), do: row
  defp maybe_put_depth(row, depth), do: Map.put(row, :depth, depth)

  defp attach_path(row, %Spec{path: false}, _chains), do: row

  defp attach_path(row, _spec, chains) do
    path =
      chains
      |> Map.get(row.id, [])
      |> Enum.flat_map(fn ancestor ->
        case Bee.Id.parse(ancestor.id) do
          {:ok, id} -> [%{id: id, title: ancestor.title, status: ancestor.status}]
          {:error, :invalid_id} -> []
        end
      end)

    Map.put(row, :path, path)
  end

  defp attach_rollup(row, %Spec{fold: false}, _rollups), do: row

  defp attach_rollup(row, _spec, rollups),
    do: Map.put(row, :rollup, Map.fetch!(rollups, row.id))
end
