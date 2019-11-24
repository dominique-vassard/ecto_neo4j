defmodule EctoNeo4j.Cql.RelationshipTest do
  use ExUnit.Case, async: false
  @moduletag :supported

  alias Bolt.Sips.Types.{Node, Relationship}

  alias Ecto.Adapters.Neo4j.Cql.Relationship, as: RelationshipCql

  test "create/1" do
    start_node = %Bolt.Sips.Types.Node{
      id: "12903da6-5d46-417b-9cab-bd82766c868b",
      labels: ["User"],
      properties: %{
        first_name: "John",
        last_name: "Doe"
      }
    }

    end_node = %Node{
      id: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
      labels: ["Post"],
      properties: %{
        rel_wrote: %{when: ~D[2018-02-01]},
        text: "This is the second",
        title: "Second",
        user_uuid: "12903da6-5d46-417b-9cab-bd82766c868b"
      }
    }

    relationship = %Relationship{
      type: "WROTE",
      properties: %{when: ~D[2018-02-01]},
      start: start_node,
      end: end_node
    }

    assert {cql, params} = RelationshipCql.create(relationship)

    assert cql == """
           MATCH
             (n1:User {uuid: {start_node_uuid}}),
             (n2:Post {uuid: {end_node_uuid}})
           CREATE
             (n1)-[rel:WROTE]->(n2)
           SET
             rel.when = {when}\n
           """

    assert params == %{
             end_node_uuid: "727289bc-ec28-4459-a9dc-a51ee6bfd6ab",
             start_node_uuid: "12903da6-5d46-417b-9cab-bd82766c868b",
             when: ~D[2018-02-01]
           }
  end
end
