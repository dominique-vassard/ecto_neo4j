defmodule Ecto.Adapters.Neo4j do
  @behaviour Ecto.Adapter

  defmacro __before_compile__(_env), do: :ok

  def ensure_all_started(_config, type) do
    {:ok, _} = Application.ensure_all_started(:bolt_sips, type)
  end

  def init(config) do
    opts = config || Application.get_env(:bolt_sips, Bolt)

    {:ok, Bolt.Sips.child_spec(opts), %{}}
  end

  defdelegate checkout(adapter_meta, opts, fun), to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  def dumpers(:uuid, _type), do: [&Ecto.UUID.cast/1, :string]
  def dumpers(_primitive, type), do: [type]

  def loaders(:uuid, _type), do: [&Ecto.UUID.dump/1, Ecto.UUID]
  def loaders(_primitive, type), do: [type]

  @behaviour Ecto.Adapter.Queryable
  defdelegate prepare(operation, query), to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  defdelegate execute(repo, query_meta, query_cache, sources, preprocess, opts \\ []),
    to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  defdelegate preload(struct_or_structs_or_nil, preloads, opts \\ []),
    to: Ecto.Adapters.Neo4j.Behaviour.Repo

  defdelegate stream(adapter_meta, query_meta, query_cache, params, opts \\ []),
    to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  @behaviour Ecto.Adapter.Schema
  defdelegate autogenerate(field_type), to: Ecto.Adapters.Neo4j.Behaviour.Schema

  defdelegate insert_all(
                adapter_meta,
                schema_meta,
                header,
                entries,
                on_conflict,
                returning,
                options
              ),
              to: Ecto.Adapters.Neo4j.Behaviour.Schema

  defdelegate insert(adapter_meta, schema_meta, fields, on_conflict, returning, options),
    to: Ecto.Adapters.Neo4j.Behaviour.Schema

  @doc """
  Insert data into database and create relationship if necessary.
  """
  @spec insert(Ecto.Repo.t(), Ecto.Schema.t() | Ecto.Changeset.t(), Keyword.t()) ::
          Ecto.Schema.t()
  def insert(repo, data, opts \\ []) do
    repo.insert(data, opts)
    |> Ecto.Adapters.Neo4j.Behaviour.Relationship.process_relationships()
  end

  @doc """
  Same as insert/3 but raises in case of error.
  """
  def insert!(repo, data, opts \\ []) do
    case insert(repo, data, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
      error -> raise error
    end
  end

  defdelegate update(adapter_meta, schema_meta, fields, filters, returning, options),
    to: Ecto.Adapters.Neo4j.Behaviour.Schema

  @doc """
  Updates a changeset using its primary key.

  This alternative to `Ecto.Repo.update` takes care of relationships, therefore they can be added / deleted.

  Use `put_assoc` to update relationships.

  ## Example

    # Remove all relationship of a kind
    MyRepo.get!(User, "ec1741ba-28f2-47fc-8a96-a3c5e24c42da")
    |> Ecto.Adapters.Neo4j.preload(:wrote_post)
    |> Ecto.Changeset.change()
    |> put_assoc(:wrote_post, [])
    |> Ecto.Adapters.Neo4j.update()

    # Add a new relationship
    new_post = MyRepo.insert(%Post{title: "New post"})

    user = MyRepo.get!(User, "ec1741ba-28f2-47fc-8a96-a3c5e24c42da")
    |> Ecto.Adapters.Neo4j.preload(:wrote_post)

    user
    |> Ecto.Changeset.change()
    |> put_assoc(:wrote_post, user.wrote_post ++ [new_post])
    |> Ecto.Adapters.Neo4j.update()
  """
  @spec update(Ecto.Changeset.t(), module, Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, any()}
  def update(changeset, repo, opts \\ [])

  def update(%Ecto.Changeset{valid?: true} = changeset, repo, opts) do
    %{__struct__: schema} = changeset.data

    %{changes: new_changes, new_data: new_data} =
      Enum.reduce(changeset.changes, %{changes: changeset.changes, new_data: %{}}, fn {field,
                                                                                       change},
                                                                                      changes ->
        cond do
          field in schema.__schema__(:associations) and is_list(change) ->
            new_data =
              Enum.map(change, fn c ->
                Ecto.Adapters.Neo4j.Behaviour.Relationship.update(
                  c.action,
                  changeset.data,
                  c.data,
                  field
                )
              end)
              |> Enum.reject(&is_nil/1)

            %{
              changes
              | changes: Map.drop(changes.changes, [field]),
                new_data: Map.put(changes.new_data, field, new_data)
            }

          Kernel.match?("rel_" <> _, Atom.to_string(field)) ->
            Ecto.Adapters.Neo4j.Behaviour.Relationship.update_data(
              schema,
              field,
              change,
              changeset.data
            )

            string_change =
              Enum.map(change, fn {k, v} -> {Atom.to_string(k), v} end)
              |> Map.new()

            rel_data = Map.merge(Map.fetch!(changeset.data, field), string_change)

            %{
              changes
              | changes: Map.drop(changes.changes, [field]),
                new_data: Map.put(%{}, field, rel_data)
            }

          true ->
            changes
        end
      end)

    top_level_data =
      Enum.reduce(new_data, changeset.data, fn {key, value}, data ->
        Map.put(data, key, value)
      end)

    Map.put(changeset, :data, top_level_data)
    |> Map.replace!(:changes, new_changes)
    |> repo.update(opts)
  end

  def update(changeset, repo, opts) do
    repo.update(changeset, opts)
  end

  @doc """
  Same as `update\3` but raises in case of error
  """
  @spec update!(Ecto.Changeset.t(), module, Keyword.t()) :: Ecto.Schema.t()
  def update!(changeset, repo, opts) do
    case update(changeset, repo, opts) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise error
    end
  end

  defdelegate delete(adapter_meta, schema_meta, filters, options),
    to: Ecto.Adapters.Neo4j.Behaviour.Schema

  @behaviour Ecto.Adapter.Storage
  defdelegate storage_up(config), to: Ecto.Adapters.Neo4j.Storage
  defdelegate storage_down(config), to: Ecto.Adapters.Neo4j.Storage
  defdelegate execute_ddl(repo, ddl, opts), to: Ecto.Adapters.Neo4j.Storage.Migrator

  defdelegate lock_for_migrations(repo, query, opts, fun),
    to: Ecto.Adapters.Neo4j.Storage.Migrator

  def supports_ddl_transaction?(), do: false

  @behaviour Ecto.Adapter.Transaction
  defdelegate transaction(adapter_meta, opts, fun_or_multi),
    to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  defdelegate rollback(adapter_meta, opts), to: Ecto.Adapters.Neo4j.Behaviour.Queryable
  defdelegate in_transaction?(adapter_meta), to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  ######################
  # ADDITIONAL HELPERS #
  ######################
  @doc """
  Execute given query on the databsse.
  This will return a `Bolt.Sips.Response`.

  ## Example
      iex> cql = "RETURN {num} AS n"
      iex> params = %{num: 5}
      ...> {:ok,
      ...>   %Bolt.Sips.Response{
      ...>     bookmark: _,
      ...>     fields: ["n"],
      ...>     notifications: [],
      ...>     plan: nil,
      ...>     profile: nil,
      ...>     records: [[5]],
      ...>     results: [%{"n" => 5}],
      ...>     stats: [],
      ...>     type: "r"
      ...>   }} = Ecto.Adapters.Neo4j.query(cql, params)
      iex> :ok
      :ok
  """
  defdelegate query(cql, params \\ %{}, opts \\ []), to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  @doc """
  Same as query/3 but raises in case of error.
  """
  defdelegate query!(cql, params \\ %{}, opts \\ []), to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  @doc """
  Execute given query in batch.
  There is two type of batches:
    - `:basic` will use `LIMIT` to loop until every node is touched
    - `:with_skip` will use `SKIP` and `LIMIT` until every node is touched

  In order to work, the query must contains:
    - for `:basic`, `LIMIT {limit}`
    - for `:with_skip`, `SKIP {skip} LIMIT {limit}`
    - in any case: `RETURN COUNT(my_nodes) AS nb_touched_nodes` with `my_nodes` being the nodes
      you're working on

  The `LIMIT` is set by default to 10_000, but you can set your aown value via the option
  `:chunk_size`

  ## Example

      # :basic example
      iex> cql = "
      ...> MATCH
      ...>     (n:Test)
      ...> WITH
      ...>   n AS n
      ...> LIMIT
      ...>   {limit}
      ...> DETACH DELETE n
      ...> RETURN
      ...>   COUNT(n) AS nb_touched_nodes
      ...> "
      iex> Ecto.Adapters.Neo4j.batch_query(cql)
      {:ok, []}
      # :with_skip example
      iex> cql = "
      ...> MATCH
      ...>     (n:Test)
      ...> WITH
      ...>   n AS n
      ...> ORDER BY
      ...>   n.nodeId
      ...> SKIP
      ...>   {skip}
      ...> LIMIT
      ...>   {limit}
      ...> SET
      ...>   n.value = {new_value}
      ...> RETURN
      ...>   COUNT(n) AS nb_touched_nodes
      ...> "
      iex> Ecto.Adapters.Neo4j.batch_query(cql, %{new_value: 5}, :with_skip)
      {:ok, []}
      # :basic example with `chunk_size` option specifiedd
      iex> cql = "
      ...> MATCH
      ...>     (n:Test)
      ...> WITH
      ...>   n AS n
      ...> LIMIT
      ...>   {limit}
      ...> DETACH DELETE n
      ...> RETURN
      ...>   COUNT(n) AS nb_touched_nodes
      ...> "
      iex> Ecto.Adapters.Neo4j.batch_query(cql, %{}, :basic, chunk_size: 20_000)
      {:ok, []}
  """
  defdelegate batch_query(cql, params \\ %{}, batch_type \\ :basic, opts \\ []),
    to: Ecto.Adapters.Neo4j.Behaviour.Queryable

  @doc """
  Same as batch_query!/4 but raises in case of error.
  """
  defdelegate batch_query!(cql, params \\ %{}, batch_type \\ :basic, opts \\ []),
    to: Ecto.Adapters.Neo4j.Behaviour.Queryable
end
