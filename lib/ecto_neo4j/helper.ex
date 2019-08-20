defmodule EctoNeo4j.Helper do
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
