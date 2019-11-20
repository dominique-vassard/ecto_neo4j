defmodule EctoNeo4j.Cql.Relationship do
  @moduledoc """
  Cypher query builder for Node
  """
  alias Bolt.Sips.Types.Relationship

  @doc """
  Create a relationship to fit the model:
  (start_node)-[:relationship]->(end_node)

  Use Bolt.Sips.Types.Node and Bolt.Sips.Types.Relationship

  # Example

  iex> start_node = %Bolt.Sips.Types.Node{
  ...>   id: "12903da6-5d46-417b-9cab-bd82766c868b",
  ...>   labels: ["User"],
  ...>   properties: %{
  ...>     __meta__: #Ecto.Schema.Metadata<:loaded, "User">,
  ...>     __struct__: EctoNeo4j.Integration.User,
  ...>     first_name: "John",
  ...>     last_name: "Doe",
  ...>     posts: [
  ...>       %EctoNeo4j.Integration.Post{
  ...>         __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
  ...>         author: #Ecto.Association.NotLoaded<association :author is not loaded>,
  ...>         rel_wrote: %{when: ~D[2018-01-01]},
  ...>         text: "This is the first",
  ...>         title: "First",
  ...>         user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  ...>         uuid: "ae830851-9e93-46d5-bbf7-23ab99846497"
  ...>       },
  ...>       %EctoNeo4j.Integration.Post{
  ...>         __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
  ...>         author: #Ecto.Association.NotLoaded<association :author is not loaded>,
  ...>         rel_wrote: %{when: ~D[2018-02-01]},
  ...>         text: "This is the second",
  ...>         title: "Second",
  ...>         user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
  ...>         uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab"
  ...>       }
  ...>     ]
  ...>   }
  ...> }
  iex> end_node = %Bolt.Sips.Types.Node{
  ...>   id: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
  ...>   labels: ["Post"],
  ...>   properties: %{
  ...>     __meta__: #Ecto.Schema.Metadata<:loaded, "Post">,
  ...>     __struct__: EctoNeo4j.Integration.Post,
  ...>     author: #Ecto.Association.NotLoaded<association :author is not loaded>,
  ...>     rel_wrote: %{when: ~D[2018-02-01]},
  ...>     text: "This is the second",
  ...>     title: "Second",
  ...>     user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
  ...>   }
  ...> }
  iex> relationship = %Bolt.Sips.Types.Relationship{
  ...>   end: end_node,
  ...>   id: nil,
  ...>   properties: %{when: ~D[2018-02-01]},
  ...>   start: start_node,
  ...>   type: "WROTE"
  ...> }
  iex> EctoNeo4j.Cql.Relationship.create(relationship)
  {"MATCH\n  (n1:User {uuid: {start_node_uuid}}),\n  (n2:Post {uuid: {end_node_uuid}})\nMERGE\n  (n1)-[rel:WROTE]->(n2)\nSET\n  rel.when = {when}\n\n",
    %{
      end_node_uuid: "ae830851-9e93-46d5-bbf7-23ab99846497",
      start_node_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      when: ~D[2018-01-01]
    }}
    {"MATCH\n  (n1:User {uuid: {start_node_uuid}}),\n  (n2:Post {uuid: {end_node_uuid}})\nMERGE\n  (n1)-[rel:WROTE]->(n2)\nSET\n  rel.when = {when}\n\n",
    %{
      end_node_uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
      start_node_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
      when: ~D[2018-02-01]
    }}
  """
  @spec create(Relationship.t()) :: {String.t(), map()}
  def create(%Relationship{start: start_node, end: end_node} = relationship) do
    data_to_set =
      relationship.properties
      |> Enum.map(fn {k, _} -> "rel.#{k} = {#{k}}" end)

    cql_set =
      if length(data_to_set) > 0 do
        """
        SET
          #{Enum.join(data_to_set, ",  \n")}
        """
      end

    cql = """
    MATCH
      (n1:#{start_node.labels |> List.first()} {uuid: {start_node_uuid}}),
      (n2:#{end_node.labels |> List.first()} {uuid: {end_node_uuid}})
    CREATE
      (n1)-[rel:#{relationship.type}]->(n2)
    #{cql_set}
    """

    params =
      %{
        start_node_uuid: start_node.id,
        end_node_uuid: end_node.id
      }
      |> Map.merge(relationship.properties)

    {cql, params}
  end
end
