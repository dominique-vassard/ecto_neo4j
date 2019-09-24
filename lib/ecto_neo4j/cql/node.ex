defmodule EctoNeo4j.Cql.Node do
  @doc """
  Returns Cypher query to get one node given its uuid

  ### Parameters

    - node_label: The node label to search on

  ### Example

      iex> EctoNeo4j.Cql.Node.get_by_uuid("Post")
      "MATCH\\n  (n:Post)\\nWHERE\\n  n.uuid = {uuid}\\nRETURN\\n  n\\n"
  """
  @spec get_by_uuid(String.t()) :: String.t()
  def get_by_uuid(node_label) do
    """
    MATCH
      (n:#{node_label})
    WHERE
      n.uuid = {uuid}
    RETURN
      n
    """
  end

  @doc """
  Returns cypher query and params to insert a new node.

  ## Example

      iex> data = %{title: "New title", uuid: "a-valid-uuid"}
      iex> EctoNeo4j.Cql.Node.insert("Post", data)
      {"CREATE
        (n:Post)
      SET
        n.title = {title},  \\nn.uuid = {uuid}\\n
      RETURN
        n
      ", %{title: "New title", uuid: "a-valid-uuid"}}

      # With returning fields specified
      iex> data = %{title: "New title", uuid: "a-valid-uuid"}
      iex> EctoNeo4j.Cql.Node.insert("Post", data, [:uuid])
      {"CREATE
        (n:Post)
      SET
        n.title = {title},  \\nn.uuid = {uuid}\\n
      RETURN
        n.uuid AS uuid
      ", %{title: "New title", uuid: "a-valid-uuid"}}
  """
  @spec insert(String.t(), map(), list()) :: {String.t(), map()}
  def insert(node_label, data, return \\ []) do
    data_to_set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)

    cql_set =
      if length(data_to_set) > 0 do
        """
        SET
          #{Enum.join(data_to_set, ",  \n")}
        """
      end

    return_fields =
      if length(return) > 0 do
        return
        |> Enum.map(fn field -> "n.#{field} AS #{field}" end)
        |> Enum.join(", ")
      else
        "n"
      end

    cql = """
    CREATE
      (n:#{node_label})
    #{cql_set}
    RETURN
      #{return_fields}
    """

    {cql, data}
  end

  # def insert(node_label, data) do

  # end

  @doc """
  Returns cypher query to update node data.

  ## Example

      iex> data = %{title: "New title"}
      iex> filters = %{id: 5}
      iex> EctoNeo4j.Cql.Node.update("Post", data, filters)
      {"MATCH
        (n:Post)
      WHERE
        n.id = {f_id}
      SET
        n.title = {title}
      RETURN
        n
      ", %{f_id: 5, title: "New title"}}
  """
  @spec update(String.t(), map(), map()) :: {String.t(), map()}
  def update(node_label, data, filters \\ %{}) do
    set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql_where =
      if map_size(filters) > 0 do
        where =
          filters
          |> Enum.map(fn {k, _} -> "n.#{k} = {f_#{k}}" end)
          |> Enum.join(" AND ")

        "WHERE\n  " <> where
      end

    formated_filters =
      filters
      |> Enum.map(fn {k, v} ->
        {"f_#{Atom.to_string(k)}" |> String.to_atom(), v}
      end)
      |> Map.new()

    cql = """
    MATCH
      (n:#{node_label})
    #{cql_where}
    SET
      #{set}
    RETURN
      n
    """

    params = Map.merge(data, formated_filters)

    {cql, params}
  end

  @doc """
  Returns cypher query to delete a node.

  ## Example

      iex> EctoNeo4j.Cql.Node.delete("Post", %{uuid: "a-valid-uuid"})
      {"MATCH
        (n:Post)
      WHERE
        n.uuid = {uuid}
      DETACH DELETE
        n
      RETURN
        n
      ", %{uuid: "a-valid-uuid"}}
  """
  @spec delete(String.t(), map()) :: {String.t(), map()}
  def delete(node_label, filters) do
    where =
      filters
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(" AND ")

    cql = """
    MATCH
      (n:#{node_label})
    WHERE
      #{where}
    DETACH DELETE
      n
    RETURN
      n
    """

    {cql, filters}
  end

  @doc """
  Returns cypher query to delete all database data.

  ## Example

      iex> EctoNeo4j.Cql.Node.delete_all()
      "MATCH
        (n)
      DETACH DELETE
        n
      "
  """
  @spec delete_all() :: String.t()
  def delete_all() do
    """
    MATCH
      (n)
    DETACH DELETE
      n
    """
  end

  @doc """
  Returns cypher query to delete all given nodes.
  This operation shoudl be performed as a btach for performance reason.

  ## Example

      iex> EctoNeo4j.Cql.Node.delete_nodes("Post")
      "MATCH
        (n:Post)
      WITH
        n AS n
      LIMIT
        {limit}
      DETACH DELETE
        n
      RETURN
        COUNT(n) AS nb_touched_nodes
      "
  """
  @spec delete_nodes(String.t()) :: String.t()
  def delete_nodes(node_label) do
    """
    MATCH
      (n:#{node_label})
    WITH
      n AS n
    LIMIT
      {limit}
    DETACH DELETE
      n
    RETURN
      COUNT(n) AS nb_touched_nodes
    """
  end

  @doc """
  Builds a cypher query for given `node_label`, `where`, `return` parts.

  ## Example

      # with default `where` and `return`
      iex> EctoNeo4j.Cql.Node.build_query(:match, "Post")
      "MATCH
        (n:Post)\\n\\n\\n\\n
      RETURN
        n\\n\\n\\n
      "

      # with everything defined
      iex> node_label = "Post"
      iex> where = "title = {title}"
      iex> return = "n"
      iex> EctoNeo4j.Cql.Node.build_query(:match, node_label, where, "", return)
      "MATCH
        (n:Post)
      WHERE
      title = {title}\\n\\n\\n\\n
      RETURN
        n\\n\\n\\n
      "

      # for deleting
      iex> EctoNeo4j.Cql.Node.build_query(:delete, "Post")
      "MATCH
        (n:Post)\\n\\n\\n
      DETACH DELETE
        n\\n
      RETURN
        n\\n\\n\\n
      "
  """
  @spec build_query(
          :match | :delete | :update,
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          nil | integer(),
          nil | integer()
        ) ::
          String.t()
  def build_query(
        query_type,
        node_label,
        where \\ "",
        update \\ "",
        return \\ "n",
        order_by \\ "",
        limit \\ nil,
        skip \\ nil,
        is_batch? \\ false
      ) do
    cql_where =
      if String.length(where) > 0 do
        """
        WHERE
        #{where}
        """
      end

    cql_update =
      if String.length(update) > 0 do
        """
        SET
          #{update}
        """
      end

    cql_order_by =
      if String.length(order_by) > 0 do
        """
        ORDER BY
          #{order_by}
        """
      end

    cql_delete =
      if query_type == :delete do
        """
        DETACH DELETE
          n
        """
      end

    cql_limit =
      if limit do
        """
        LIMIT #{limit}
        """
      end

    cql_skip =
      if skip do
        """
        SKIP #{skip}
        """
      end

    {return, cql_skip, cql_limit, cql_order_by, cql_batch} =
      batch_cql(is_batch?, query_type, return, cql_skip, cql_limit, cql_order_by)

    """
    MATCH
      (n:#{node_label})
    #{cql_where}
    #{cql_batch}
    #{cql_update}
    #{cql_delete}
    RETURN
      #{return}
    #{cql_order_by}
    #{cql_skip}
    #{cql_limit}
    """
  end

  defp batch_cql(false, _, return, skip, limit, order_by) do
    {return, skip, limit, order_by, ""}
  end

  defp batch_cql(true, query_type, _, _, _, _) do
    return = "COUNT(n) AS nb_touched_nodes"
    skip = ""
    limit = ""
    order_by = ""

    cql_batch_skip =
      if query_type == :update do
        "SKIP {skip}"
      end

    batch = """
    WITH
    n AS n
    #{cql_batch_skip}
    LIMIT
    {limit}
    """

    {return, skip, limit, order_by, batch}
  end

  @doc """
  Handle creation of non unique indexes.

  ## Example

      iex> EctoNeo4j.Cql.Node.create_index("Post", [:title])
      "CREATE INDEX ON :Post(title)"
      iex> EctoNeo4j.Cql.Node.create_index("Post", [:title, :author])
      "CREATE INDEX ON :Post(title, author)"

  """
  @spec create_index(String.t(), [String.t()]) :: String.t()
  def create_index(node_label, columns) do
    manage_index(node_label, columns, :create)
  end

  @doc """
  Handle deletion of non unique indexes.

  ## Example

      iex> EctoNeo4j.Cql.Node.drop_index("Post", [:title])
      "DROP INDEX ON :Post(title)"
      iex> EctoNeo4j.Cql.Node.drop_index("Post", [:title, :author])
      "DROP INDEX ON :Post(title, author)"

  """
  @spec drop_index(String.t(), [String.t()]) :: String.t()
  def drop_index(node_label, columns) do
    manage_index(node_label, columns, :drop)
  end

  @spec manage_index(String.t(), [String.t()], :create | :drop) :: String.t()
  defp manage_index(node_label, columns, operation) when operation in [:create, :drop] do
    op = operation |> Atom.to_string() |> String.upcase()
    "#{op} INDEX ON :#{node_label}(#{Enum.join(columns, ", ")})"
  end

  @doc """
  Handle creation of unique constraints.
  Note that uniqueness on multiple properties is only available in Enterprise Edition

  ## Example

      iex> EctoNeo4j.Cql.Node.create_constraint("Post", [:title])
      "CREATE CONSTRAINT ON (n:Post) ASSERT n.title IS UNIQUE"
      iex> EctoNeo4j.Cql.Node.create_constraint("Post", [:title, :author])
      "CREATE CONSTRAINT ON (n:Post) ASSERT (n.title, n.author) IS NODE KEY"

  """
  @spec create_constraint(String.t(), [String.t()]) :: String.t()
  def create_constraint(node_label, [column]) do
    manage_unique_constraint(node_label, column, :create)
  end

  def create_constraint(node_label, columns) do
    manage_node_key(node_label, columns, :create)
  end

  @doc """
  Handle deletion of unique constraints.
  Note that uniqueness on multiple properties is only available in Enterprise Edition

  ## Example

      iex> EctoNeo4j.Cql.Node.drop_constraint("Post", [:title])
      "DROP CONSTRAINT ON (n:Post) ASSERT n.title IS UNIQUE"
      iex> EctoNeo4j.Cql.Node.drop_constraint("Post", [:title, :author])
      "DROP CONSTRAINT ON (n:Post) ASSERT (n.title, n.author) IS NODE KEY"

  """
  @spec drop_constraint(String.t(), [String.t()]) :: String.t()
  def drop_constraint(node_label, [column]) do
    manage_unique_constraint(node_label, column, :drop)
  end

  def drop_constraint(node_label, columns) do
    manage_node_key(node_label, columns, :drop)
  end

  @spec manage_unique_constraint(String.t(), String.t(), :create | :drop) :: String.t()
  defp manage_unique_constraint(node_label, column, operation)
       when operation in [:create, :drop] do
    op =
      operation
      |> Atom.to_string()
      |> String.upcase()

    "#{op} CONSTRAINT ON (n:#{node_label}) ASSERT n.#{column} IS UNIQUE"
  end

  defp manage_node_key(node_label, columns, operation) when operation in [:create, :drop] do
    op =
      operation
      |> Atom.to_string()
      |> String.upcase()

    cols =
      columns
      |> Enum.map(fn c -> "n.#{c}" end)
      |> Enum.join(", ")

    "#{op} CONSTRAINT ON (n:#{node_label}) ASSERT (#{cols}) IS NODE KEY"
  end

  @doc """
  Handle creation of non null constraints.

  ## Example

      iex> EctoNeo4j.Cql.Node.create_non_null_constraint("Post", :title)
      "CREATE CONSTRAINT ON (n:Post) ASSERT exists(n.title)"
  """
  @spec create_non_null_constraint(String.t(), String.t()) :: String.t()
  def create_non_null_constraint(node_label, column) do
    manage_non_null_constraint(node_label, column, :create)
  end

  @doc """
  Handle deletion of non null constraints.

  ## Example

      iex> EctoNeo4j.Cql.Node.drop_non_null_constraint("Post", :title)
      "DROP CONSTRAINT ON (n:Post) ASSERT exists(n.title)"
  """
  @spec drop_non_null_constraint(String.t(), String.t()) :: String.t()
  def drop_non_null_constraint(node_label, column) do
    manage_non_null_constraint(node_label, column, :drop)
  end

  @spec manage_non_null_constraint(String.t(), String.t(), :create | :drop) :: String.t()
  defp manage_non_null_constraint(node_label, column, operation)
       when operation in [:create, :drop] do
    op =
      operation
      |> Atom.to_string()
      |> String.upcase()

    "#{op} CONSTRAINT ON (n:#{node_label}) ASSERT exists(n.#{column |> Atom.to_string()})"
  end

  @doc """
  Builds a cypher query for listing all the constraints for a specific node.

  ## Example

      iex> EctoNeo4j.Cql.Node.list_all_constraints("Post")
      "CALL db.constraints()
      YIELD description
      WHERE description CONTAINS \\":Post\\" \\nRETURN description
      "
      iex> EctoNeo4j.Cql.Node.list_all_constraints("Post", :title)
      "CALL db.constraints()
      YIELD description
      WHERE description CONTAINS \\":Post\\" AND description CONTAINS '.title'
      RETURN description
      "
  """
  @spec list_all_constraints(String.t(), nil | atom()) :: String.t()
  def list_all_constraints(node_label, property \\ nil) do
    where_prop =
      if property do
        "AND description CONTAINS '.#{property |> Atom.to_string()}'"
      end

    """
    CALL db.constraints()
    YIELD description
    WHERE description CONTAINS ":#{node_label}" #{where_prop}
    RETURN description
    """
  end

  @doc """
  Builds a cypher query for listing all the indexes for a specific node.

  ## Example

      iex> EctoNeo4j.Cql.Node.list_all_indexes("Post")
      "CALL db.indexes()
      YIELD description
      WHERE description CONTAINS \\":Post\\" \\nRETURN description
      "
      iex> EctoNeo4j.Cql.Node.list_all_indexes("Post", :title)
      "CALL db.indexes()
      YIELD description
      WHERE description CONTAINS \\":Post\\" AND description CONTAINS 'title'
      RETURN description
      "
  """
  @spec list_all_indexes(String.t(), nil | atom()) :: String.t()
  def list_all_indexes(node_label, property \\ nil) do
    where_prop =
      if property do
        "AND description CONTAINS '#{property |> Atom.to_string()}'"
      end

    """
    CALL db.indexes()
    YIELD description
    WHERE description CONTAINS ":#{node_label}" #{where_prop}
    RETURN description
    """
  end

  @doc """
  Builds a cypher for deleting a cosntraint or an index from the database.
  Required a constraint cql similar to the one provided by `CALL db.constraints()`

  ## Example

      iex> constraint_cql = "CONSTRAINT ON ( posts:posts ) ASSERT posts.uuid IS UNIQUE"
      iex> EctoNeo4j.Cql.Node.drop_constraint_index_from_cql(constraint_cql)
      "DROP CONSTRAINT ON ( posts:posts ) ASSERT posts.uuid IS UNIQUE"
      iex> index_cql = "INDEX ON :posts(nodeId)"
      iex> EctoNeo4j.Cql.Node.drop_constraint_index_from_cql(index_cql)
      "DROP INDEX ON :posts(nodeId)"
  """
  @spec drop_constraint_index_from_cql(String.t()) :: String.t()
  def drop_constraint_index_from_cql(cql) do
    "DROP " <> cql
  end

  @doc """
  Builds a cypher for deleting a cosntraint or an index from the database.
  Required a constraint cql similar to the one provided by `CALL db.constraints()`

  ## Example

      iex> constraint_cql = "CONSTRAINT ON ( posts:posts ) ASSERT posts.uuid IS UNIQUE"
      iex> EctoNeo4j.Cql.Node.create_constraint_index_from_cql(constraint_cql)
      "CREATE CONSTRAINT ON ( posts:posts ) ASSERT posts.uuid IS UNIQUE"
      iex> index_cql = "INDEX ON :posts(nodeId)"
      iex> EctoNeo4j.Cql.Node.create_constraint_index_from_cql(index_cql)
      "CREATE INDEX ON :posts(nodeId)"
  """
  @spec create_constraint_index_from_cql(String.t()) :: String.t()
  def create_constraint_index_from_cql(cql) do
    "CREATE " <> cql
  end

  @doc """
  Bulds a query to rename a property

  ## Example

      iex> EctoNeo4j.Cql.Node.rename_property("Post", "titttle", "title")
      "MATCH
        (n:Post)
      WITH
        n AS n
      SKIP
        {skip}
      LIMIT
        {limit}
      SET
        n.title = n.titttle
      REMOVE
        n.titttle
      RETURN
        COUNT(n) AS nb_touched_nodes
      "
  """
  @spec rename_property(String.t(), String.t(), String.t()) :: String.t()
  def rename_property(node_label, old_name, new_name) do
    """
    MATCH
      (n:#{node_label})
    WITH
      n AS n
    SKIP
      {skip}
    LIMIT
      {limit}
    SET
      n.#{new_name} = n.#{old_name}
    REMOVE
      n.#{old_name}
    RETURN
      COUNT(n) AS nb_touched_nodes
    """
  end

  @doc """
  Build a query to relabel a node.

  ## Example

      iex> EctoNeo4j.Cql.Node.relabel("Post", "NewPost")
      "MATCH
        (n:Post)
      WITH
        n AS n
      LIMIT
        {limit}
      SET
        n:NewPost
      REMOVE
        n:Post
      RETURN
        COUNT(n) AS nb_touched_nodes
      "
  """
  @spec relabel(String.t(), String.t()) :: String.t()
  def relabel(old_label, new_label) do
    """
    MATCH
      (n:#{old_label})
    WITH
      n AS n
    LIMIT
      {limit}
    SET
      n:#{new_label}
    REMOVE
      n:#{old_label}
    RETURN
      COUNT(n) AS nb_touched_nodes
    """
  end
end
