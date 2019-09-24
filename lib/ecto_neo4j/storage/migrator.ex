defmodule EctoNeo4j.Storage.Migrator do
  alias EctoNeo4j.Cql.Node, as: NodeCql
  alias Ecto.Migration.{Index, Table}

  @drop_ops [:drop, :drop_if_exists]

  ################
  # DIRECT QUERY #
  ################

  def execute_ddl(_, cql, _) when is_binary(cql) do
    EctoNeo4j.Adapter.query!(cql)
    {:ok, []}
  end

  ##########
  # TABLES #
  ##########

  def execute_ddl(_, {:create, %Table{name: node_label}, operations}, _) do
    case treat_operations(node_label, operations) do
      :ok -> {:ok, []}
      {:ok, _} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def execute_ddl(_, {:create_if_not_exists, %Table{name: node_label}, operations}, _) do
    treat_operations(node_label, operations)
    {:ok, []}
  end

  def execute_ddl(_, {operation, %Table{name: node_label}}, _) when operation in @drop_ops do
    node_label
    |> NodeCql.delete_nodes()
    |> EctoNeo4j.Adapter.batch_query!()

    drop_all_constraints_and_indexes(node_label)

    {:ok, []}
  end

  def execute_ddl(_, {:rename, %Table{name: old_name}, %Table{name: new_name}}, _) do
    NodeCql.relabel(old_name, new_name)
    |> EctoNeo4j.Adapter.batch_query!()

    ci_list = [
      NodeCql.list_all_constraints(old_name),
      NodeCql.list_all_indexes(old_name)
    ]

    move_constraints_indexes(ci_list, old_name, new_name)
    {:ok, []}
  end

  ###########
  # COLUMNS #
  ###########

  def execute_ddl(_, {:alter, %Table{name: node_label}, operations}, _) do
    treat_operations(node_label, operations)

    {:ok, []}
  end

  def execute_ddl(_, {:rename, %Table{name: node_label}, old_name, new_name}, _) do
    NodeCql.rename_property(node_label, old_name, new_name)
    |> EctoNeo4j.Adapter.batch_query!(%{}, :with_skip)

    # Move constraints and indexes to the new property
    ci_list = [
      NodeCql.list_all_constraints(node_label, old_name),
      NodeCql.list_all_indexes(node_label, old_name)
    ]

    move_constraints_indexes(ci_list, Atom.to_string(old_name), Atom.to_string(new_name))

    {:ok, []}
  end

  ###############
  # CONSTRAINTS #
  ###############
  def execute_ddl(_, {:create, %Index{columns: cols, unique: true, table: node_label}}, _) do
    case create_constraint(node_label, cols) do
      {:ok, _} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def execute_ddl(
        _,
        {:create_if_not_exists, %Index{columns: cols, unique: true, table: node_label}},
        _
      ) do
    create_constraint(node_label, cols)
    {:ok, []}
  end

  def execute_ddl(_, {:drop, %Index{columns: cols, unique: true, table: node_label}}, _) do
    case drop_constraint(node_label, cols) do
      {:ok, _} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def execute_ddl(
        _,
        {:drop_if_exists, %Index{columns: cols, unique: true, table: node_label}},
        _
      ) do
    drop_constraint(node_label, cols)
    {:ok, []}
  end

  ###########
  # INDEXES #
  ###########

  def execute_ddl(_, {:create, %Index{columns: cols, table: node_label}}, _) do
    case create_index(node_label, cols) do
      {:ok, _} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def execute_ddl(_, {:create_if_not_exists, %Index{columns: cols, table: node_label}}, _) do
    create_index(node_label, cols)
    {:ok, []}
  end

  def execute_ddl(_, {:drop, %Index{columns: cols, table: node_label}}, _) do
    case drop_index(node_label, cols) do
      {:ok, _} -> {:ok, []}
      {:error, error} -> raise Bolt.Sips.Exception, error.message
    end
  end

  def execute_ddl(_, {:drop_if_exists, %Index{columns: cols, table: node_label}}, _) do
    drop_index(node_label, cols)
    {:ok, []}
  end

  def execute_ddl(_, [create: _], _) do
    {:ok, []}
  end

  ########################
  # PRIVATES AND HElPERS #
  ########################
  defp treat_operations(node_label, operations) do
    case do_treat_operations(node_label, operations) do
      data when map_size(data) == 0 ->
        :ok

      data ->
        {cql, params} = NodeCql.update(node_label, data)

        EctoNeo4j.Adapter.query(cql, params)
    end
  end

  @add_ops [:add, :modify]
  defp do_treat_operations(node_label, operations, data \\ %{})

  defp do_treat_operations(_, [], data) do
    data
  end

  defp do_treat_operations(node_label, [{:remove, col} | operations], data) do
    new_data = Map.put(data, col, nil)

    drop_all_constraints_and_indexes(node_label, col)

    do_treat_operations(node_label, operations, new_data)
  end

  defp do_treat_operations(node_label, [{op, col, _, [{:null, true} | _]} | operations], data)
       when op in @add_ops do
    NodeCql.drop_non_null_constraint(node_label, col)
    |> EctoNeo4j.Adapter.query()

    do_treat_operations(node_label, operations, data)
  end

  defp do_treat_operations(node_label, [{op, col, _, [{:null, false} | _]} | operations], data)
       when op in @add_ops do
    NodeCql.create_non_null_constraint(node_label, col)
    |> EctoNeo4j.Adapter.query()

    do_treat_operations(node_label, operations, data)
  end

  defp do_treat_operations(
         node_label,
         [{op, col, _, [{:primary_key, true} | _]} | operations],
         data
       )
       when op in @add_ops do
    NodeCql.create_constraint(node_label, [col])
    |> EctoNeo4j.Adapter.query()

    do_treat_operations(node_label, operations, data)
  end

  defp do_treat_operations(
         node_label,
         [{op, col, _, [{:primary_key, false} | _]} | operations],
         data
       )
       when op in @add_ops do
    NodeCql.drop_constraint(node_label, [col])
    |> EctoNeo4j.Adapter.query()

    do_treat_operations(node_label, operations, data)
  end

  defp do_treat_operations(node_label, [{op, _, _, _} | operations], data)
       when op in @add_ops do
    do_treat_operations(node_label, operations, data)
  end

  defp create_constraint(node_label, cols) do
    NodeCql.create_constraint(node_label, cols)
    |> EctoNeo4j.Adapter.query()
  end

  defp drop_constraint(node_label, cols) do
    NodeCql.drop_constraint(node_label, cols)
    |> EctoNeo4j.Adapter.query()
  end

  defp create_index(node_label, cols) do
    NodeCql.create_index(node_label, cols)
    |> EctoNeo4j.Adapter.query()
  end

  defp drop_index(node_label, cols) do
    NodeCql.drop_index(node_label, cols)
    |> EctoNeo4j.Adapter.query()
  end

  defp drop_all_constraints_and_indexes(node_label, col \\ nil) do
    [NodeCql.list_all_constraints(node_label, col), NodeCql.list_all_indexes(node_label, col)]
    |> Enum.map(fn cql ->
      EctoNeo4j.Adapter.query!(cql)
      |> Map.get(:records, [])
    end)
    |> List.flatten()
    |> Enum.map(&NodeCql.drop_constraint_index_from_cql/1)
    |> Enum.map(&EctoNeo4j.Adapter.query/1)
  end

  defp move_constraints_indexes(cstr_idx_list, from, to) do
    ci_list =
      cstr_idx_list
      |> Enum.map(fn cql ->
        EctoNeo4j.Adapter.query!(cql)
        |> Map.get(:records, [])
      end)
      |> List.flatten()

    ci_list
    |> Enum.map(fn cql ->
      cql
      |> String.replace(from, to)
      |> NodeCql.create_constraint_index_from_cql()
      |> EctoNeo4j.Adapter.query()
    end)

    ci_list
    |> Enum.map(&NodeCql.drop_constraint_index_from_cql/1)
    |> Enum.map(&EctoNeo4j.Adapter.query/1)
  end

  def lock_for_migrations(_repo, query, _opts, fun) do
    query |> fun.()
  end
end
