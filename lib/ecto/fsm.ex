defmodule Ecto.FSM do
  @moduledoc """
  Handle Ecto structures status through FSM

  Provides macros for defining FSM

  Defines FSM with `transition/2` and `bypass/2` macros.

  Caller module is added the following functions:
  * `fsm() :: Ecto.FSM.specs()`
  * `docs() :: Ecto.FSM.docs()`

  Transition functions must return `Ecto.FSM.transition_ret`.

  Examples:

      iex> defmodule Elixir.Door do
      ...>   use Ecto.FSM
      ...> 
      ...>   @doc "Close to open"
      ...>   @to [:opened]
      ...>   transition closed({:open, _}, s) do
      ...>     {:next_state, :opened, s}
      ...>   end
      ...> 
      ...>   @doc "Close to close"
      ...>   transition closed({:close, _}, s) do
      ...>     {:next_state, :closed, s}
      ...>   end
      ...> 
      ...>   transition closed({:else, _}, s) do
      ...>     {:next_state, :closed, s}
      ...>   end
      ...> 
      ...>   @doc "Open to open"
      ...>   transition opened({:open, _}, s) do
      ...>     {:next_state, :opened, s}
      ...>   end
      ...> 
      ...>   @doc "Open to close"
      ...>   @to [:closed]
      ...>   transition opened({:close, _}, s) do
      ...>     {:next_state, :closed, s}
      ...>   end
      ...> 
      ...>   transition opened({:else, _}, s) do
      ...>     {:next_state, :opened, s}
      ...>   end
      ...>
      ...>   @doc "Force the door"
      ...>   bypass force(_, s) do
      ...>     {:next_state, :destroyed, s}
      ...>   end
      ...> end
      ...> Door.fsm()
      %{
        {:closed, :close} => {Door, [:closed]}, {:closed, :else} => {Door, [:closed]},
        {:closed, :open} => {Door, [:opened]}, {:opened, :close} => {Door, [:closed]},
        {:opened, :else} => {Door, [:opened]}, {:opened, :open} => {Door, [:opened]}
      }
      ...> Door.docs()
      %{
        {:transition_doc, :closed, :close} => "Close to close",
        {:transition_doc, :closed, :else} => nil,
        {:transition_doc, :closed, :open} => "Close to open",
        {:transition_doc, :opened, :close} => "Open to close",
        {:transition_doc, :opened, :else} => nil,
        {:transition_doc, :opened, :open} => "Open to open",
        {:event_doc, :force} => "Force the door"
      }
  """
  alias Ecto.Changeset
  alias Ecto.Multi
  alias Ecto.FSM.Machine
  alias Ecto.FSM.Schema
  alias Ecto.FSM.State

  @type trans :: atom
  @type params :: term
  @type handler :: module

  @type action :: {State.name(), trans}
  @type result :: {handler, [State.name()]}
  @type specs :: %{action => result}
  @type bypasses :: %{trans => handler}

  @type doc_key :: {:transition_doc, State.name(), trans} | {:event_doc, trans}
  @type doc :: String.t() | nil

  @type docs :: %{doc_key => doc}
  @type info :: {:transition, doc} | {:bypass, doc}

  @type transition_ret :: {:next_state, State.name(), State.t()} | {:keep_state, State.t()}
  @type transition :: ({trans, params}, State.t() -> transition_ret)

  defmacro __using__(_opts) do
    quote do
      import Ecto.FSM, only: [transition: 2, bypass: 2]

      @fsm %{}
      @bypasses %{}
      @docs %{}
      @to nil
      @__states_names__ []

      @before_compile Ecto.FSM
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Returns this handler's FSM as `spec()`
      """
      def fsm, do: @fsm

      @doc """
      Returns this handler's FSM bypasses as `spec()`
      """
      def event_bypasses, do: @bypasses

      @doc """
      Returns this FSM's doc map
      """
      def docs, do: @docs

      @doc """
      Returns this FSM's states names
      """
      def states_names, do: @__states_names__
    end
  end

  @doc """
  Define a function of type `transition` describing a state and its
  transition. The function name is the state name, the transition is the
  first argument. A state object can be modified and is the second argument.

  ```
  deftrans opened({:close_door, _params}, state) do
    {:next_state, :closed, state}
  end
  ```
  """
  defmacro transition({state, _meta, [action, _data]} = signature, body_block) do
    do_block = Keyword.get(body_block, :do)

    transition =
      case action do
        {:_, _, nil} -> :_
        {{:_, _, _}, _params} -> :_
        {t, _params} when is_atom(t) -> t
      end

    next_states =
      do_block
      |> find_nextstates(state)
      |> Enum.uniq()

    quote do
      state_name = unquote(state)
      trans = unquote(transition)
      next_states = @to || unquote(next_states)

      @fsm Map.put(@fsm, {state_name, trans}, {__MODULE__, next_states})
      @__states_names__ [state_name | @__states_names__] ++ next_states |> Enum.uniq()

      doc =
        __MODULE__
        |> Module.get_attribute(:doc)
        |> case do
          nil -> nil
          {_line, doc} -> doc
          doc when is_binary(doc) -> doc
        end

      @docs Map.put(@docs, {:transition_doc, state_name, trans}, doc)
      def unquote(signature), do: unquote(do_block)
      @to nil
    end
  end

  @doc """
  Define a function of type `bypass`, ie which can be applied on any state
  """
  defmacro bypass({trans, _meta, _args} = signature, body_block) do
    quote do
      @bypasses Map.put(@bypasses, unquote(trans), __MODULE__)
      doc =
        __MODULE__
        |> Module.get_attribute(:doc)
        |> case do
          nil -> nil
          {_line, doc} -> doc
          doc when is_binary(doc) -> doc
        end

      @docs Map.put(@docs, {:event_doc, unquote(trans)}, doc)
      def unquote(signature), do: unquote(body_block[:do])
    end
  end

  @doc """
  Executes action on a changeset with associated FSM

  Returns a Multi or function acceptable by `Ecto.transaction/2` callback
  """
  @spec action(Changeset.t(), trans, params) :: Changeset.t() | Multi.t()
  def action(%Changeset{valid?: false} = cs, _action, _params), do: cs

  def action(%Changeset{} = cs, action, params) do
    if Machine.action_available?(cs, action) do
      do_action(cs, action, params)
    else
      Changeset.add_error(
        cs,
        Schema.State.field(cs),
        "action '#{action}' not available from state '#{Machine.State.state_name(cs)}'"
      )
    end
  end

  @doc """
  Returns new state from Multi changes returned by a transition
  """
  @spec state(changes :: map) :: State.t()
  def state(%{__fsm_state__: state}), do: state

  ###
  ### Priv
  ###
  defp do_action(%Changeset{} = cs, action, params) do
    case Machine.event(cs, {action, params}) do
      {:ok, cs} ->
        cs

      {:error, :illegal_action} ->
        Changeset.add_error(cs, Schema.State.field(cs), "illegal action: #{action}")

      {:error, err} ->
        Changeset.add_error(cs, Schema.State.field(cs), inspect(err))
    end
  end

  defp find_nextstates({:keep_state, _state_ast}, state_name),
    do: [state_name]

  defp find_nextstates({:{}, _, [:next_state, state_name, _state_ast]}, _)
       when is_atom(state_name),
       do: [state_name]

  defp find_nextstates({_, _, asts}, state_name),
    do: find_nextstates(asts, state_name)

  defp find_nextstates({_, asts}, state_name),
    do: find_nextstates(asts, state_name)

  defp find_nextstates(asts, state_name) when is_list(asts),
    do: Enum.flat_map(asts, fn ast -> find_nextstates(ast, state_name) end)

  defp find_nextstates(_, _),
    do: []
end
