defmodule Ecto.Adapters.Neo4j.Behaviour.Repo do
  alias Ecto.Adapters.Neo4j.Query

  defmodule PreloadInfo do
    defstruct [:name, :upward?, :queryable, :unique?, :foreign_key, :search_key]

    @type t :: %__MODULE__{
            name: atom(),
            upward?: boolean(),
            queryable: module(),
            unique?: boolean(),
            foreign_key: atom(),
            search_key: atom()
          }
  end

  @doc """
  Preloads all associations on the given struct or structs.

  Unsupported features:
    - Nested associaiton preloads
    - custom query preloads

  ## Examples

      # Use a single atom to preload an association
      posts = Repo.preload posts, :comments

      # Use a list of atoms to preload multiple associations
      posts = Repo.preload posts, [:comments, :authors]
  """
  @spec preload(nil | [Ecto.Schema.t()] | Ecto.Schema.t(), atom | [atom], Keyword.t()) ::
          nil | nil | [Ecto.Schema.t()] | Ecto.Schema.t()
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

      preload_info = preload_info(preload, schema.__schema__(:association, preload))

      node_schema = %Query.NodeExpr{
        variable: "n_s",
        labels: [schema.__schema__(:source)]
      }

      node_queryable = %Query.NodeExpr{
        variable: "n_q",
        labels: [preload_info.queryable.__schema__(:source)]
      }

      schema_name =
        if preload_info.upward? do
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
        if preload_info.upward? do
          %{bare_relationship | start: node_queryable, end: node_schema}
        else
          %{bare_relationship | start: node_schema, end: node_queryable}
        end

      condition = %Ecto.Adapters.Neo4j.Condition{
        source: "n_s",
        field: preload_info.search_key,
        operator: :==,
        value: Atom.to_string(preload_info.search_key),
        conditions: nil
      }

      params = Map.put(%{}, preload_info.search_key, Map.fetch!(struct, preload_info.search_key))

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

  @spec preload_info(atom, map) :: PreloadInfo.t()
  defp preload_info(preload, %Ecto.Association.BelongsTo{} = preload_data) do
    %PreloadInfo{
      name: preload,
      upward?: true,
      queryable: preload_data.queryable,
      unique?: true,
      foreign_key: preload_data.owner_key,
      search_key: preload_data.related_key
    }
  end

  defp preload_info(preload, %Ecto.Association.Has{} = preload_data) do
    %PreloadInfo{
      name: preload,
      upward?: false,
      queryable: preload_data.queryable,
      unique?: false,
      foreign_key: preload_data.related_key,
      search_key: preload_data.owner_key
    }
  end

  @spec build_struct(Ecto.Schema.t(), PreloadInfo.t(), Bolt.Sips.Response.t(), String.t()) ::
          Ecto.Schema.t()
  defp build_struct(struct, %{upward?: true, unique?: true} = preload_info, results, rel_name) do
    result = List.first(results.results)

    build_unique_struct(struct, preload_info, results.records)
    |> add_relationship_data(result, rel_name)
    |> Map.put(
      preload_info.foreign_key,
      Map.fetch!(result, "n_q." <> Atom.to_string(preload_info.search_key))
    )
  end

  defp build_struct(struct, %{upward?: false, unique?: false} = preload_info, results, rel_name) do
    related_fields = preload_info.queryable.__schema__(:fields)

    relateds =
      Enum.map(results.records, fn record ->
        fields = Enum.zip(related_fields, record)

        result =
          Enum.zip(results.fields, record)
          |> Map.new()

        struct(preload_info.queryable, fields)
        |> add_relationship_data(result, rel_name)
        |> Map.put(preload_info.foreign_key, Map.fetch!(struct, preload_info.search_key))
      end)

    struct
    |> Map.put(preload_info.name, relateds)
  end

  @spec build_unique_struct(Ecto.Schema.t(), PreloadInfo.t(), list()) :: Ecto.Schema.t()
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

  @spec add_relationship_data(Ecto.Schema.t(), map, String.t()) :: Ecto.Schema.t()
  defp add_relationship_data(struct, result, rel_name) do
    struct
    |> Map.put(
      String.to_atom(rel_name),
      Map.fetch!(result, rel_name).properties
    )
  end
end
