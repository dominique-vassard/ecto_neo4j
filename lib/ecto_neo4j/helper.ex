defmodule EctoNeo4j.Helper do
  @moduledoc """
  Useful helpers
  """

  @doc """
  Manage id transformation from and to database.
  As Neo4j uses a field name `id` to store its internal id, the Ecto.Schema defined field `id` is
  transformed into `nodeI` to avoid any problem.

  ## Examples

      iex> to_db_data = %{id: 3, value: "test"}
      iex> from_db_data = EctoNeo4j.Helper.manage_id(to_db_data, :to_db)
      %{nodeId: 3, value: "test"}
      iex> EctoNeo4j.Helper.manage_id(from_db_data, :from_db)
      %{id: 3, value: "test"}

  """
  def manage_id(%{nodeId: node_id} = data, :from_db) do
    data
    |> Map.put(:id, node_id)
    |> Map.drop([:nodeId])
  end

  def manage_id(data, :from_db) do
    data
  end

  def manage_id(%{id: id} = data, :to_db) do
    data
    |> Map.put(:nodeId, id)
    |> Map.drop([:id])
  end

  def manage_id(data, :to_db), do: data
end
