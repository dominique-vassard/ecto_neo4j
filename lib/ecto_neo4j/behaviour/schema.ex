defmodule Ecto.Adapters.Neo4j.Behaviour.Schema do
  @moduledoc false

  alias Ecto.Adapters.Neo4j.Cql.Node, as: NodeCql
  alias Ecto.Adapters.Neo4j.Condition
  alias Ecto.Adapters.Neo4j.Query

  def autogenerate(:id), do: :erlang.system_time(:microsecond)
  def autogenerate(:binary_id), do: Ecto.UUID.generate()
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  def insert_all(
        adapter,
        schema_meta,
        _header,
        entries,
        on_conflict,
        returning,
        options
      ) do
    inserts =
      entries
      |> Enum.map(fn data ->
        insert(adapter, schema_meta, data, on_conflict, returning, options)
      end)

    case returning do
      [] -> {length(inserts), nil}
      _ -> {length(inserts), Enum.map(inserts, fn {_, v} -> v end)}
    end
  end

  def insert(
        adapter_meta,
        %{source: source, schema: schema},
        fields,
        _on_conflict,
        returning,
        opts \\ []
      ) do
    returning_field =
      returning
      |> Enum.map(fn
        :id -> :nodeId
        field -> field
      end)
      |> Enum.reject(fn k ->
        case Atom.to_string(k) do
          "rel" <> _rel_type -> true
          _ -> false
        end
      end)

    # Relationships and foreign keyw should not be saved as node properties
    foreign_keys = get_foreign_keys(schema)

    insert_data =
      fields
      |> Keyword.drop(foreign_keys)
      |> Enum.reject(fn {k, _} ->
        case Atom.to_string(k) do
          "rel" <> _rel_type -> true
          _ -> false
        end
      end)

    primary_key =
      if is_nil(schema) do
        []
      else
        schema.__schema__(:primary_key)
        |> Enum.map(&Ecto.Adapters.Neo4j.Helper.translate_field(&1, :to_db))
      end

    execute(
      adapter_meta,
      NodeCql.insert(source, format_data(insert_data), primary_key, returning_field),
      opts
    )
  end

  def update(adapter_meta, %{source: source, schema: schema}, fields, filters, _returning, opts) do
    foreign_keys = get_foreign_keys(schema)

    {relationship_updates, node_fields} =
      Enum.split_with(fields, fn {k, _} -> k in foreign_keys end)

    update_relationships(schema, relationship_updates, filters)

    execute(
      adapter_meta,
      NodeCql.update(source, format_data(node_fields), format_data(filters)),
      opts
    )
  end

  @spec update_relationships(atom, Keyword.t(), Keyword.t()) :: :ok
  defp update_relationships(_schema, [], _filters) do
    :ok
  end

  defp update_relationships(schema, fields, filters) do
    query =
      fields
      |> Keyword.to_list()
      |> Enum.reduce(Query.new(), fn field, query ->
        update_relationship(field, schema, query)
      end)

    wheres =
      filters
      |> Enum.reduce(%{where: nil, params: %{}}, fn {field, value}, clauses ->
        bound_name =
          "n_" <> String.downcase(schema.__schema__(:source)) <> "_" <> Atom.to_string(field)

        new_cond = %Condition{
          source: "n_" <> String.downcase(schema.__schema__(:source)),
          field: field,
          operator: :==,
          value: bound_name
        }

        params = Map.put(%{}, bound_name, value)

        %{
          clauses
          | where: Condition.join_conditions(clauses.where, new_cond, :and),
            params: Map.merge(clauses.params, params)
        }
      end)

    {cql, params} =
      query
      |> Query.where(wheres.where)
      |> Query.params(wheres.params)
      |> Query.to_string()

    Ecto.Adapters.Neo4j.query!(cql, params)

    :ok
  end

  @spec update_relationship({atom, any()}, atom, Query.t()) :: Query.t()
  defp update_relationship({field_key, field_value}, schema, query) do
    {parent_schema, rel_type, parent_key} =
      schema.__schema__(:associations)
      |> Enum.reduce(nil, fn assoc, acc ->
        case schema.__schema__(:association, assoc) do
          %Ecto.Association.BelongsTo{
            owner_key: ^field_key,
            field: rel_field,
            queryable: queryable,
            related_key: parent_key
          } ->
            rel_type =
              String.replace(
                Atom.to_string(rel_field),
                "_" <> String.downcase(schema.__schema__(:source)),
                ""
              )
              |> String.upcase()

            {queryable, rel_type, parent_key}

          _ ->
            acc
        end
      end)

    start_label = parent_schema.__schema__(:source)

    start_node = %Query.NodeExpr{
      variable: "n_" <> String.downcase(start_label),
      labels: [start_label]
    }

    end_label = schema.__schema__(:source)

    end_node = %Query.NodeExpr{
      variable: "n_" <> String.downcase(end_label),
      labels: [end_label]
    }

    relationship = %Query.RelationshipExpr{
      start: start_node,
      end: end_node,
      type: rel_type,
      variable: "rel_" <> String.downcase(start_label)
    }

    query
    |> Query.match([relationship])
    |> Query.delete([relationship])
    |> add_new_relationship(relationship, parent_key, field_value)
  end

  @spec add_new_relationship(Query.t(), Query.RelationshipExpr.t(), atom, any) :: Query.t()
  def add_new_relationship(query, _relationship, _parent_key, nil) do
    query
  end

  def add_new_relationship(query, relationship, parent_field, parent_field_value) do
    start_label = List.first(relationship.start.labels)
    end_label = List.first(relationship.end.labels)

    new_node = %Query.NodeExpr{
      variable: "new_n_" <> String.downcase(start_label),
      labels: [start_label]
    }

    merge_rel = %Query.RelationshipExpr{
      index: 0,
      variable: "",
      start: %Query.NodeExpr{
        variable: new_node.variable
      },
      end: %Query.NodeExpr{variable: "n_" <> String.downcase(end_label)},
      type: relationship.type
    }

    merge_bound = new_node.variable <> "_" <> Atom.to_string(parent_field)

    merge_cond = %Condition{
      source: new_node.variable,
      field: parent_field,
      operator: :==,
      value: merge_bound
    }

    params = Map.put(%{}, String.to_atom(merge_bound), parent_field_value)

    query
    |> Query.match([new_node])
    |> Query.merge([
      %Query.MergeExpr{
        expr: merge_rel
      }
    ])
    |> Query.where(merge_cond)
    |> Query.params(params)
  end

  def delete(adapter_meta, %{source: source}, filters, opts) do
    execute(adapter_meta, NodeCql.delete(source, format_data(filters)), opts)
  end

  defp execute(%{pid: pool}, {cql, params}, opts) do
    default_role =
      Application.get_env(:ecto_neo4j, Ecto.Adapters.Neo4j, bolt_role: :direct)
      |> Keyword.get(:bolt_role)

    bolt_role = Keyword.get(opts, :bolt_role, default_role)
    conn = Ecto.Adapters.Neo4j.Behaviour.Queryable.get_conn(pool, bolt_role)

    case Ecto.Adapters.Neo4j.Behaviour.Queryable.query(cql, params, conn: conn) do
      {:ok, %Bolt.Sips.Response{results: [%{"n" => _record}]}} ->
        {:ok, []}

      {:ok, %Bolt.Sips.Response{records: [record]}} ->
        {:ok, record}

      {:error,
       %Bolt.Sips.Error{
         code: "Neo.ClientError.Schema.ConstraintValidationFailed",
         message: message
       }} ->
        [_, label, property] =
          Regex.run(~r/.*`(?<label>[a-zA-Z_]+)`.*`(?<property>[a-zA-Z_]+)`/, message)

        {:invalid, [{:unique, "#{label}_#{property}_index"}]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_data(data) do
    data
    |> Map.new()
    |> Ecto.Adapters.Neo4j.Helper.manage_id(:to_db)
  end

  @doc """
  Retrieve foreign keys related to the parent for the given schema.

  ## Example

      iex> Ecto.Adapters.Neo4j.Behaviour.Schema.get_foreign_keys(MyApp.Post)
      [:author]
  """
  @spec get_foreign_keys(nil | module()) :: [atom()]
  def get_foreign_keys(nil) do
    []
  end

  def get_foreign_keys(schema) do
    Enum.map(schema.__schema__(:associations), fn assoc ->
      schema.__schema__(:association, assoc)
    end)
    |> Enum.filter(fn
      %Ecto.Association.BelongsTo{} -> true
      _ -> false
    end)
    |> Enum.map(fn data -> Map.get(data, :owner_key) end)
  end
end
