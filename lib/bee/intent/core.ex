defmodule Bee.Intent.Core do
  @moduledoc false

  alias Bee.Query.Spec

  @intents [:what_next]

  @spec known?(atom()) :: boolean()
  def known?(intent), do: intent in @intents

  @spec resolve(atom(), keyword()) :: {:ok, Spec.t()} | {:error, term()}
  def resolve(:what_next, opts) when is_list(opts) do
    with :ok <- validate_opts(opts) do
      spec =
        [
          status: "open",
          assigned_to: Keyword.get(opts, :agent),
          project_id: Keyword.get(opts, :project),
          limit: Keyword.get(opts, :limit),
          order_by: [priority: :desc, created_at: :asc]
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      Spec.new(spec)
    end
  end

  def resolve(:what_next, _opts), do: {:error, :invalid_spec}
  def resolve(intent, _opts) when is_atom(intent), do: {:error, {:unknown_core_intent, intent}}

  defp validate_opts(opts) do
    allowed = [:agent, :project, :limit]

    if Keyword.keyword?(opts) do
      case Enum.find(opts, fn {key, _value} -> key not in allowed end) do
        nil -> :ok
        {key, _value} -> {:error, {:invalid_intent_option, key}}
      end
    else
      {:error, :invalid_spec}
    end
  end
end
