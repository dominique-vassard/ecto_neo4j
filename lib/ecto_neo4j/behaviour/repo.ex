defmodule Ecto.Adapters.Neo4j.Behaviour.Repo do
  alias Ecto.Adapters.Neo4j.Query

  def preload(struct_or_structs_or_nil, preloads, opts \\ [])

  def preload(nil, _preloads, _opts) do
    nil
  end

  def preload(structs, preloads, opts) when is_list(structs) and is_list(preloads) do
    Enum.map(structs, &do_preload(&1, preloads, opts))
  end

  def preload(structs, preload, opts) when is_atom(preload) do
    preload(structs, [preload], opts)
  end

  def preload(struct, preloads, opts) when is_map(struct) do
    preload([struct], preloads, opts)
    |> List.first()
  end

  defp do_preload(base_struct, preloads, _opts) do
    base_struct =
      Enum.reduce(preloads, base_struct, fn preload, struct ->
        Map.put(struct, preload, nil)
      end)

    Enum.reduce(preloads, base_struct, fn preload, struct ->
      schema = struct.__struct__

      preload_info =
        case schema.__schema__(:association, preload) do
          %Ecto.Association.BelongsTo{queryable: queryable} ->
            %{
              name: preload,
              is_upward?: true,
              queryable: queryable,
              is_unique?: true
            }

          %Ecto.Association.Has{queryable: queryable} ->
            %{
              name: preload,
              is_upward?: false,
              queryable: queryable,
              is_unique?: false
            }
        end

      node_schema = %Query.NodeExpr{
        variable: "n_s",
        labels: [schema.__schema__(:source)]
      }

      node_queryable = %Query.NodeExpr{
        variable: "n_q",
        labels: [preload_info.queryable.__schema__(:source)]
      }

      schema_name =
        if preload_info.is_upward? do
          schema
        else
          preload_info.queryable
        end
        |> Module.split()
        |> List.last()
        |> String.downcase()

      rel_field_name =
        preload
        |> Atom.to_string()
        |> String.replace("_" <> schema_name, "")

      bare_relationship = %Query.RelationshipExpr{
        type: String.upcase(rel_field_name),
        variable: "rel_" <> rel_field_name
      }

      relationship =
        if preload_info.is_upward? do
          %{bare_relationship | start: node_queryable, end: node_schema}
        else
          %{bare_relationship | start: node_schema, end: node_queryable}
        end

      primary_key = schema.__schema__(:primary_key) |> List.first()

      condition = %Ecto.Adapters.Neo4j.Condition{
        source: "n_s",
        field: primary_key,
        operator: :==,
        value: Atom.to_string(primary_key),
        conditions: nil
      }

      params = Map.put(%{}, primary_key, Map.fetch!(struct, primary_key))

      fields =
        Enum.map(preload_info.queryable.__schema__(:fields), fn field ->
          %Query.FieldExpr{
            variable: "n_q",
            name: field
          }
        end)

      {cql, params} =
        Query.new()
        |> Query.match([relationship])
        |> Query.where(condition)
        |> Query.params(params)
        |> Query.return(%Query.ReturnExpr{fields: fields ++ [relationship]})
        |> Query.to_string()

      results = Ecto.Adapters.Neo4j.query!(cql, params)

      build_struct(struct, preload_info, results, relationship.variable)
    end)
  end

  defp build_struct(
         struct,
         %{is_upward?: true, is_unique?: true} = preload_info,
         results,
         relationship_name
       ) do
    parent_pk = preload_info.queryable.__schema__(:primary_key) |> List.first()

    foreign_key =
      preload_info.name
      |> Atom.to_string()
      |> Kernel.<>("_uuid")
      |> String.to_atom()

    result = List.first(results.results)

    build_unique_struct(struct, preload_info, results.records)
    |> Map.put(
      String.to_atom(relationship_name),
      Map.fetch!(result, relationship_name).properties
    )
    |> Map.put(foreign_key, Map.fetch!(result, "n_q." <> Atom.to_string(parent_pk)))
  end

  defp build_struct(
         struct,
         %{is_upward?: false, is_unique?: false} = preload_info,
         results,
         relationship_name
       ) do
    # build_multiple_structs(struct, preload_info, results.records)

    related_fields = preload_info.queryable.__schema__(:fields)

    foreign_key =
      preload_info.name
      |> Atom.to_string()
      |> Kernel.<>("_uuid")
      |> String.to_atom()

    parent_pk = struct.__struct__.__schema__(:primary_key) |> List.first()

    relateds =
      Enum.map(results.records, fn record ->
        fields = Enum.zip(related_fields, record)

        result =
          Enum.zip(results.fields, record)
          |> Map.new()

        struct(preload_info.queryable, fields)
        |> Map.put(
          String.to_atom(relationship_name),
          Map.fetch!(result, relationship_name).properties
        )
        |> Map.put(foreign_key, Map.fetch!(struct, parent_pk))
      end)

    struct
    |> Map.put(preload_info.name, relateds)
  end

  defp build_unique_struct(struct, %{name: preload, queryable: queryable}, data) do
    related_fields = queryable.__schema__(:fields)

    related =
      Enum.map(data, fn record ->
        fields = Enum.zip(related_fields, record)
        struct(queryable, fields)
      end)
      |> List.first()

    struct
    |> Map.put(preload, related)
  end

  # defp build_multiple_structs(struct, %{name: preload, queryable: queryable}, data, rel_name) do
  #   related_fields = queryable.__schema__(:fields)

  #   relateds =
  #     Enum.map(data, fn record ->
  #       fields = Enum.zip(related_fields, record)
  #       struct(queryable, fields)
  #     end)

  #   # struct
  #   # |> Map.put(preload, relateds)
  # end

  def is_upward_preload?(schema, preload) do
    case schema.__schema__(:association, preload) do
      %Ecto.Association.BelongsTo{} ->
        false

      %Ecto.Association.Has{} ->
        true
    end
  end
end
