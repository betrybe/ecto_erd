defmodule Ecto.ERDTest do
  use ExUnit.Case
  alias Ecto.ERD.{DBML, Node, Field}

  defmodule ProjectTypeEnum do
    use Ecto.Type

    def type, do: :string

    def cast(value), do: {:ok, value}

    def dump(value), do: {:ok, value}

    def load(value), do: {:ok, value}

    def __enums__, do: ~w(private public)
  end

  test inspect(&DBML.enums_mapping/1) do
    result =
      [
        %Node{
          source: "credentials",
          fields: [
            Field.new(%{
              name: :flow,
              type: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:simple, :complex])}
            })
          ]
        },
        %Node{
          source: "invitations",
          fields: [
            Field.new(%{
              name: :flow,
              type: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:simple, :complex])}
            })
          ]
        },
        %Node{
          source: "users",
          fields: [
            Field.new(%{
              name: :status,
              type:
                {:parameterized, Ecto.Enum,
                 Ecto.Enum.init(values: [:active, :suspended, :invited])}
            })
          ]
        },
        %Node{
          source: "admins",
          fields: [
            Field.new(%{
              name: :status,
              type: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:active, :suspended])}
            })
          ]
        },
        %Node{
          source: "projects",
          fields: [
            Field.new(%{
              name: :status,
              type: {:parameterized, Ecto.Enum, Ecto.Enum.init(values: [:live, :closed])}
            }),
            Field.new(%{name: :type, type: ProjectTypeEnum})
          ]
        }
      ]
      |> Ecto.ERD.DBML.enums_mapping()

    assert result == %{
             ["admins", :status] => {"admins_status", ["active", "suspended"]},
             ["credentials", :flow] => {"flow", ["complex", "simple"]},
             ["invitations", :flow] => {"flow", ["complex", "simple"]},
             ["projects", :status] => {"projects_status", ["closed", "live"]},
             ["projects", :type] => {"type", ["private", "public"]},
             ["users", :status] => {"users_status", ["active", "invited", "suspended"]}
           }
  end
end
