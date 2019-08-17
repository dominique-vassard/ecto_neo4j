defmodule EctoNeo4j.Cql.Node do
  alias EctoNeo4j.Cql.Helper

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
  Returns cypher query to insert a node with the given properties, along with
  the parameters to use.

  Note: if `uuid` is in the data, it will be used. Otherwise a `nodeId` property will be
   automatically created.

  ### Example:
      # With uuid
      iex> data = %{uuid: "unique_id", title: "My post title"}
      %{title: "My post title", uuid: "unique_id"}
      iex> EctoNeo4j.Cql.Node.insert("Post", data)
      {"MERGE
        (n:Post {uuid: {uuid}})
      SET
      n.title = {title}, \\nn.uuid = {uuid}RETURN
        n
      ", %{title: "My post title", uuid: "unique_id"}}

      # Without uuid, automatic reation of nodeId
      iex> data = %{title: "My post title"}
      %{title: "My post title"}
      iex> EctoNeo4j.Cql.Node.insert("Post", data)
      {"MERGE
        (sequence:Sequence {name: 'generalSequence'})
      ON CREATE
        SET sequence.current = 1
      ON MATCH
        SET sequence.current = sequence.current + 1
      WITH sequence.current AS node_id
      MERGE
        (n:Post {nodeId: node_id})
      SET
      n.title = {title}RETURN
        n
      ", %{title: "My post title"}}
  """
  @spec insert(String.t(), map()) :: {String.t(), map()}
  def insert(node_label, %{uuid: _} = data) do
    cql_set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql =
      """
      MERGE
        (n:#{node_label} {uuid: {uuid}})
      SET
      """ <>
        cql_set <>
        """
        RETURN
          n
        """

    {cql, data}
  end

  def insert(node_label, data) do
    cql_set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql =
      """
      MERGE
        (sequence:Sequence {name: 'generalSequence'})
      ON CREATE
        SET sequence.current = 1
      ON MATCH
        SET sequence.current = sequence.current + 1
      WITH sequence.current AS node_id
      MERGE
        (n:#{node_label} {nodeId: node_id})
      SET
      """ <>
        cql_set <>
        """
        RETURN
          n
        """

    {cql, data}
  end

  def insert_new(node_label, data) do
    cql_set =
      data
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql_id =
      case Map.has_key?(data, :uuid) do
        true -> "uuid: {uuid}"
        _ -> "nodeId: {node_id}"
      end

    cql =
      """
      MERGE
      (n:#{node_label} {#{cql_id}})
      SET
      """ <>
        cql_set <>
        """
        RETURN
          n
        """

    {cql, data}
  end

  @doc """
  Returns cypher query to update node data.

  ## Example

      iex> data = %{title: "New title"}
      iex> primary_key = %{name: :id, value: 5}
      iex> EctoNeo4j.Cql.Node.update("Post", data, primary_key)
      {"MATCH
        (n:Post {id: {id}})
      SET
      n.title = {title}RETURN
        n
      ",%{id: 5, title: "New title"}}
  """
  @spec update(String.t(), map(), %{name: atom(), value: any}) :: {String.t(), map()}
  def update(node_label, data, primary_key) do
    r =
      data
      |> Enum.filter(fn {k, _} -> k != :uuid end)
      |> Enum.map(fn {k, _} -> "n.#{k} = {#{k}}" end)
      |> Enum.join(", \n")

    cql =
      """
      MATCH
        (n:#{node_label} {#{primary_key.name}: {#{primary_key.name}}})
      SET
      """ <>
        r <>
        """
        RETURN
          n
        """

    params =
      data
      |> Map.put(primary_key.name, primary_key.value)

    {cql, params}
  end

  @doc """
  Returns cypher query to delete a node.

  ## Example

      iex> primary_key = %{name: :id, value: 5}
      iex> EctoNeo4j.Cql.Node.delete("Post", primary_key)
      {"MATCH
        (n:Post {id: {id}})
      DETACH DELETE n
      RETURN
      n
      ",%{id: 5}}
  """
  @spec delete(String.t(), %{name: atom(), value: any}) :: {String.t(), map()}
  def delete(node_label, primary_key) do
    cql = """
    MATCH
      (n:#{node_label} {#{primary_key.name}: {#{primary_key.name}}})
    DETACH DELETE n
    RETURN
    n
    """

    params = %{} |> Map.put(primary_key.name, primary_key.value)

    {cql, params}
  end

  @doc """
  Builds a cypher query for given `node_label`, `where`, `return` parts.

  ## Example

      # with default `where` and `return`
      iex> EctoNeo4j.Cql.Node.build_query("Post")
      "MATCH
        (n:Post)\\n
      RETURN
        n
      "
      # with everything defined
      iex> node_label = "Post"
      iex> where = "title = {title}"
      iex> return = "n"
      iex> EctoNeo4j.Cql.Node.build_query(node_label, where, return)
      "MATCH
        (n:Post)
      WHERE
        title = {title}\\n
      RETURN
        n
      "
  """
  @spec build_query(String.t(), String.t(), String.t()) :: String.t()
  def build_query(node_label, where \\ "", return \\ "n") do
    cql_where =
      if String.length(where) > 0 do
        """
        WHERE
          #{where}
        """
      end

    """
    MATCH
      (n:#{node_label})
    #{cql_where}
    RETURN
      #{return}
    """
  end
end
