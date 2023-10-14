defmodule MishkaDeveloperToolsTest.GuardedStructTest do
  use ExUnit.Case, async: true
  alias MishkaDeveloperTools.Helper.Derive.ValidationDerive
  ############## (▰˘◡˘▰) GuardedStructTest Data (▰˘◡˘▰) ##############
  # Store the bytecode so we can get information from it.
  {:module, _name, bytecode, _exports} =
    defmodule TestStruct do
      use GuardedStruct

      guardedstruct do
        field(:int, integer())
        field(:string, String.t())
        field(:string_with_default, String.t(), default: "default")
        field(:mandatory_int, integer(), enforce: true)
      end

      def enforce_keys, do: @enforce_keys
    end

  {:module, _name, bytecode_opaque, _exports} =
    defmodule OpaqueTestStruct do
      use GuardedStruct

      guardedstruct opaque: true do
        field(:int, integer())
      end
    end

  defmodule EnforcedGuardedStruct do
    use GuardedStruct

    guardedstruct enforce: true do
      field(:enforced_by_default, term())
      field(:not_enforced, term(), enforce: false)
      field(:with_default, integer(), default: 1)
      field(:with_false_default, boolean(), default: false)
      field(:with_nil_default, term(), default: nil)
    end

    def enforce_keys, do: @enforce_keys
  end

  defmodule TestModule do
    use GuardedStruct

    guardedstruct module: Struct do
      field(:field, term())
    end
  end

  {:module, _name, bytecode_noalias, _exports} =
    defmodule TestStructNoAlias do
      use GuardedStruct

      guardedstruct do
        field(:test, TestModule.TestSubModule.t())
      end
    end

  @bytecode bytecode
  @bytecode_opaque bytecode_opaque
  @bytecode_noalias bytecode_noalias

  ############## (▰˘◡˘▰) GuardedStructTest Tests functions (▰˘◡˘▰) ##############
  test "generates the struct with its defaults" do
    assert TestStruct.__struct__() == %TestStruct{
             int: nil,
             string: nil,
             string_with_default: "default",
             mandatory_int: nil
           }
  end

  test "enforces keys for fields with `enforce: true`" do
    assert TestStruct.enforce_keys() == [:mandatory_int]
  end

  test "enforces keys by default if `enforce: true` is set at top-level" do
    assert :enforced_by_default in EnforcedGuardedStruct.enforce_keys()
  end

  test "does not enforce keys for fields explicitely setting `enforce: false" do
    refute :not_enforced in EnforcedGuardedStruct.enforce_keys()
  end

  test "does not enforce keys for fields with a default value" do
    refute :with_default in EnforcedGuardedStruct.enforce_keys()
  end

  test "generates a type for the struct" do
    # Define a second struct with the type expected for TestStruct.
    {:module, _name, bytecode2, _exports} =
      defmodule TestStruct2 do
        defstruct [:int, :string, :string_with_default, :mandatory_int]

        @type t() :: %__MODULE__{
                int: integer() | nil,
                string: String.t() | nil,
                string_with_default: String.t(),
                mandatory_int: integer()
              }
      end

    # the second struct with the name of the first one).
    fields = [:int, :string, :string_with_default, :mandatory_int]

    assert check_type(:t, bytecode2, fields)
    assert check_type(:t, @bytecode, fields)
  end

  test "generates an opaque type if `opaque: true` is set" do
    # Define a second struct with the type expected for TestStruct.
    {:module, _name, bytecode_expected, _exports} =
      defmodule TestStruct3 do
        defstruct [:int]

        @opaque t() :: %__MODULE__{
                  int: integer() | nil
                }
      end

    fields = [:int]

    assert check_type(:t, @bytecode_opaque, fields, :opaque)
    assert check_type(:t, bytecode_expected, fields, :opaque)
  end

  test "generates the struct in a submodule if `module: ModuleName` is set" do
    assert TestModule.Struct.__struct__() == %TestModule.Struct{field: nil}
  end

  test "GuardedStruct macros are available only in the guardedstruct block" do
    assert_raise CompileError, ~r"cannot compile module", fn ->
      defmodule ScopeTest do
        use GuardedStruct

        guardedstruct do
          field(:in_scope, term())
        end

        # Let’s try to use field/2 outside the block.
        field(:out_of_scope, term())
      end
    end
  end

  test "the name of a field must be an atom" do
    assert_raise ArgumentError, "a field name must be an atom, got 3", fn ->
      defmodule InvalidStruct do
        use GuardedStruct

        guardedstruct do
          field(3, integer())
        end
      end
    end
  end

  test "it is not possible to add twice a field with the same name" do
    assert_raise ArgumentError, "the field :name is already set", fn ->
      defmodule InvalidStruct do
        use GuardedStruct

        guardedstruct do
          field(:name, String.t())
          field(:name, integer())
        end
      end
    end
  end

  test "aliases are properly resolved in types" do
    {:module, _name, bytecode_actual, _exports} =
      defmodule TestStructWithAlias do
        use GuardedStruct

        guardedstruct do
          alias TestModule.TestSubModule

          field(:test, TestSubModule.t())
        end
      end

    fields = [:test]

    assert check_type(:t, @bytecode_noalias, fields)
    assert check_type(:t, bytecode_actual, fields)
  end

  test "create builder function to test enforce keys and normal keys" do
    defmodule TestStructBuilder do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end
    end

    {:error, :required_fields, [:name]} = assert TestStructBuilder.builder(%{title: "user"})

    {:ok, data} = assert TestStructBuilder.builder(%{name: "shahryar", title: "user"})

    assert is_struct(data)

    enforce_keys = TestStructBuilder.enforce_keys()
    enforce_keys_by_field = TestStructBuilder.enforce_keys(:name)
    keys = TestStructBuilder.keys()
    keys_by_field = TestStructBuilder.keys(:name)

    [:name] = assert enforce_keys
    assert enforce_keys_by_field
    [:title, :name] = assert keys
    assert keys_by_field
  end

  test "use builder to test an allowed map as its params" do
    defmodule TestStructBuilderAllowedMap do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end
    end

    test_map = %{name: "shahryar", title: "user", test: "test"}

    {:ok, _data} = assert TestStructBuilderAllowedMap.builder(test_map)
  end

  test "use builder to get validator inside its module" do
    defmodule TestStructInsideValidatorBuilder do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, _data} =
      assert TestStructInsideValidatorBuilder.builder(%{name: "shahryar", title: "user"})

    {:error, :bad_parameters, [%{message: _msg, field: :name}]} =
      assert TestStructInsideValidatorBuilder.builder(%{name: 1, title: "user"})
  end

  test "use builder to get main_validator inside its module" do
    defmodule TestStructInsideMainValidatorBuilder do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end

      def main_validator(value) do
        {:ok, value}
      end
    end

    {:ok, _data} =
      assert TestStructInsideMainValidatorBuilder.builder(%{name: "mishka", title: "org"})
  end

  test "use builder to get validator inside another module" do
    defmodule GuardedStructTest.AnotherModule do
      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end
    end

    defmodule TestStructAnotherValidatorBuilder do
      alias GuardedStructTest.AnotherModule
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, validator: {AnotherModule, :validator})
        field(:title, String.t())
      end

      # You can not use it, but it is mentioned here for test clarity
      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, _data} =
      assert TestStructAnotherValidatorBuilder.builder(%{name: "mishka", title: "org"})

    {:error, :bad_parameters, [%{message: _msg, field: :name}]} =
      assert TestStructAnotherValidatorBuilder.builder(%{name: 1, title: "user"})
  end

  test "use builder to get main_validator inside another module" do
    defmodule GuardedStructTest.AnotherMainModule do
      def main_validator(value) do
        {:ok, value}
      end
    end

    defmodule TestStructAnotherMainValidatorBuilder do
      alias GuardedStructTest.AnotherMainModule
      use GuardedStruct

      guardedstruct main_validator: {AnotherMainModule, :main_validator} do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end
    end

    {:ok, _data} =
      assert TestStructAnotherMainValidatorBuilder.builder(%{name: "mishka", title: "org"})
  end

  test "use builder to Sanitize - derive: sanitize(trim, lowercase)" do
    defmodule TestStructWithSanitizeDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derive: "sanitize(trim, upcase)")
        field(:title, String.t(), derive: "sanitize(capitalize)")
      end
    end

    {:ok, data} = TestStructWithSanitizeDerive.builder(%{name: " mishka ", title: "org"})
    "MISHKA" = assert data.name
    "Org" = assert data.title
  end

  test "use builder to Validation and Lack of validation" do
    defmodule TestStructWithValidationDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derive: "validate(not_empty)")
        field(:title, String.t(), derive: "validate(not_empty, time)")
      end
    end

    {:error, :bad_parameters,
     [
       %{message: _msg1, field: :name, action: :not_empty},
       %{message: _msg2, field: :title, action: :type},
       %{message: _msg3, field: :title, action: :not_empty}
     ]} = assert TestStructWithValidationDerive.builder(%{name: "", title: ""})

    defmodule TestStructWithValidationDerive1 do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derive: "validate(not_empty)")
        field(:title, String.t(), derive: "validate(not_empty)")
      end
    end

    {:ok, _data} =
      assert TestStructWithValidationDerive1.builder(%{name: "mishka", title: "group"})
  end

  test "use builder to Sanitize and Validation" do
    defmodule TestStructWithValidationAndValidationDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derive: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derive: "validate(not_empty)")
      end
    end

    {:ok, data} =
      TestStructWithValidationAndValidationDerive.builder(%{name: " mishka ", title: "org"})

    "MISHKA" = assert data.name

    {:error, :bad_parameters, [%{field: :title, action: :not_empty, message: _msg}]} =
      assert TestStructWithValidationAndValidationDerive.builder(%{name: " mishka ", title: ""})
  end

  test "use builder to Derive and field validator" do
    defmodule TestStructBuilderWithValidationDeriveAndFieldValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derive: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derive: "sanitize(trim, capitalize) validate(not_empty)")
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, "Mishka   "}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndFieldValidator.builder(%{
        name: "fake_mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Org" = assert data.title

    {:error, :bad_parameters, [%{message: "No, never", field: :name}]} =
      assert TestStructBuilderWithValidationDeriveAndFieldValidator.builder(%{
               name: 1,
               title: "  org"
             })
  end

  test "use builder to Derive and main validator" do
    defmodule TestStructBuilderWithValidationDeriveAndMainValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derive: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derive: "sanitize(trim, capitalize) validate(not_empty)")
      end

      def main_validator(value) do
        {:ok, Map.merge(value, %{title: "    Group"})}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndMainValidator.builder(%{
        name: "mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Group" = assert data.title
  end

  test "use builder to Derive and both validator and Lack of validation" do
    defmodule TestStructBuilderWithValidationDeriveAndBothValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derive: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derive: "sanitize(trim, capitalize) validate(not_empty)")
        field(:nickname, String.t(), derive: "validate(not_empty, time)")
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, "Mishka   "}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end

      def main_validator(value) do
        {:ok, Map.merge(value, %{title: "    Group"})}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndBothValidator.builder(%{
        name: "fake_mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Group" = assert data.title

    {:error, :bad_parameters,
     [
       %{message: _msg1, field: :nickname, action: :type},
       %{message: _msg2, field: :nickname, action: :not_empty}
     ]} =
      assert TestStructBuilderWithValidationDeriveAndBothValidator.builder(%{
               name: "fake_mishka",
               nickname: ""
             })
  end

  defmodule TestNestedStruct do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(),
        derive:
          "sanitize(strip_tags, trim, capitalize) validate(string, not_empty, max_len=20, min_len=3)"
      )

      field(:family, String.t(),
        derive:
          "sanitize(basic_html, trim, capitalize) validate(string, not_empty, max_len=20, min_len=3)"
      )

      field(:age, integer(), enforce: true, derive: "validate(integer, max_len=110, min_len=18)")

      sub_field(:auth, struct(), enforce: true) do
        field(:server, String.t(), derive: "validate(regex='^[a-zA-Z]+@mishka\.group$')")

        field(:identity_provider, String.t(),
          derive: "sanitize(strip_tags, trim, lowercase) validate(not_empty)"
        )

        sub_field(:role, struct(), enforce: true) do
          field(:name, String.t(),
            derive:
              "sanitize(strip_tags, trim, lowercase) validate(enum=Atom[admin::user::banned])"
          )

          field(:action, String.t(), derive: "validate(string_boolean)")

          field(:status, String.t(),
            derive: "validate(enum=Map[%{status: 1}::%{status: 2}::%{status: 3}])"
          )
        end

        field(:last_activity, String.t(), derive: "sanitize(strip_tags, trim) validate(datetime)")
      end

      sub_field(:profile, struct()) do
        field(:site, String.t(), derive: "validate(url)")

        field(:nickname, String.t(), validator: {TestNestedStruct, :validator})
      end

      field(:username, String.t(),
        enforce: true,
        derive: "sanitize(tag=strip_tags) validate(not_empty, max_len=20, min_len=3)"
      )
    end

    def validator(:nickname, value) do
      if is_binary(value),
        do: {:ok, :nickname, value},
        else: {:error, :nickname, "Invalid nickname"}
    end

    def validator(field, value) do
      {:ok, field, value}
    end
  end

  test "nested macro field" do
    [:username, :profile, :auth, :age, :family, :name] = assert TestNestedStruct.keys()
    [:username, :auth, :age] = assert TestNestedStruct.enforce_keys()
    {:error, :required_fields, [:username, :auth, :age]} = assert TestNestedStruct.builder(%{})

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestNestedStruct{
       username: "mishka",
       profile: %MishkaDeveloperToolsTest.GuardedStructTest.TestNestedStruct.Profile{
         nickname: "mishka",
         site: "https://elixir-lang.org"
       },
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.TestNestedStruct.Auth{
         last_activity: "2023-08-20 16:54:07.841434Z",
         role: %MishkaDeveloperToolsTest.GuardedStructTest.TestNestedStruct.Auth.Role{
           action: "true",
           name: :user,
           status: %{status: 2}
         },
         identity_provider: "google",
         server: "users@mishka.group"
       },
       age: 18,
       family: "Group",
       name: "Mishka"
     }} =
      assert TestNestedStruct.builder(%{
               username: " <p>Mishka   </p>",
               auth: %{
                 server: "users@mishka.group",
                 identity_provider: "google",
                 role: %{
                   name: :user,
                   action: "true",
                   status: %{status: 2}
                 },
                 last_activity: "2023-08-20 16:54:07.841434Z"
               },
               age: 18,
               family: "group",
               name: "mishka",
               profile: %{
                 site: "https://elixir-lang.org",
                 nickname: "mishka"
               }
             })

    {:error, :bad_parameters,
     [
       %{
         field: :profile,
         errors: {:bad_parameters, [%{message: "Invalid nickname", field: :nickname}]}
       },
       %{
         field: :auth,
         errors:
           {:bad_parameters,
            [
              %{message: _msg, field: :last_activity, action: :datetime},
              %{
                field: :role,
                errors:
                  {:bad_parameters,
                   [
                     %{message: _msg1, field: :action, action: :string_boolean}
                   ]}
              }
            ]}
       }
     ]} =
      assert TestNestedStruct.builder(%{
               username: "mishka",
               auth: %{
                 server: "users@mishka.group",
                 identity_provider: "google",
                 role: %{
                   name: :admin,
                   action: "test",
                   status: %{status: 2}
                 },
                 last_activity: "20213-08-20 16:54:07.841434Z"
               },
               age: 18,
               family: "group",
               name: "mishka",
               profile: %{
                 site: "https://elixir-lang.org",
                 nickname: :test
               }
             })
  end

  test "call nested keys with :all" do
    defmodule TestCallNestedKeys do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derive: "sanitize(trim, upcase)")
        field(:title, String.t(), derive: "sanitize(trim, capitalize) validate(not_empty)")
        field(:nickname, String.t(), derive: "validate(not_empty, time)")

        sub_field(:auth, struct(), enforce: true) do
          field(:role, String.t(), derive: "validate(enum=Atom[admin, user])")
          field(:action, String.t(), derive: "validate(not_empty)")

          sub_field(:path, struct()) do
            field(:name, String.t())
            field(:mobile, String.t())
          end
        end
      end
    end

    [%{auth: [%{path: [:mobile, :name]}, :action, :role]}, :nickname, :title, :name] =
      assert TestCallNestedKeys.keys(:all)

    [%{auth: [%{path: [:mobile, :name]}, :action, :role]}, :name] =
      assert TestCallNestedKeys.enforce_keys(:all)
  end

  test "call nested struct with error true" do
    defmodule TestCallNestedStructWithError do
      use GuardedStruct

      guardedstruct error: true do
        field(:name, String.t(), derive: "validate(string)")

        sub_field(:auth, struct(), error: true) do
          field(:action, String.t(), derive: "validate(not_empty)")

          sub_field(:path, struct(), error: true) do
            field(:name, String.t())
          end
        end
      end
    end

    assert_raise TestCallNestedStructWithError.Error, fn ->
      TestCallNestedStructWithError.builder(%{name: 1}, true)
    end
  end

  test "test Only authorized data" do
    defmodule TestAuthorizeKeys do
      use GuardedStruct

      guardedstruct authorized_fields: true do
        field(:name, String.t(), derive: "validate(string)")

        sub_field(:auth, struct(), authorized_fields: true) do
          field(:action, String.t(), derive: "validate(not_empty)")

          sub_field(:path, struct()) do
            field(:name, String.t())
          end
        end
      end
    end

    {:error, :authorized_fields, [:test]} =
      assert TestAuthorizeKeys.builder(%{name: "Shahryar", test: "test"})

    {:error, :bad_parameters, [%{field: :auth, errors: {:authorized_fields, [:test]}}]} =
      assert TestAuthorizeKeys.builder(%{name: "Shahryar", auth: %{action: "admin", test: "test"}})
  end

  defmodule TestAuthStruct do
    use GuardedStruct

    guardedstruct do
      field(:action, String.t(), derive: "validate(not_empty)")

      sub_field(:path, struct(), main_validator: {TestAuthStruct, :main_validator}) do
        field(:role, String.t(), validator: {TestAuthStruct, :validator})
        field(:custom_path, String.t(), derive: "validate(not_empty)")

        sub_field(:rel, struct()) do
          field(:social, String.t(), derive: "validate(not_empty)")
        end
      end
    end

    def validator(:role, value) do
      if is_binary(value), do: {:ok, :role, value}, else: {:error, :role, "No, never"}
    end

    def validator(field, value) do
      {:ok, field, value}
    end

    def main_validator(value) do
      {:ok, value}
    end
  end

  defmodule TestUserAuthStruct do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), derive: "validate(not_empty)")
      field(:auth_path, struct(), structs: TestAuthStruct)

      sub_field(:profile, list(struct()), structs: true) do
        field(:github, String.t(), enforce: true, derive: "validate(url)")
        field(:nickname, String.t(), derive: "validate(not_empty)")
      end
    end

    def validator(:name, value) do
      if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
    end

    def validator(field, value) do
      {:ok, field, value}
    end
  end

  test "Call struct from another module with validator, derive and main_validator and list attrs" do
    {:ok, _nested_struct} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1"}},
                 %{action: "*:user", path: %{role: "3"}}
               ]
             })

    {:error, :bad_parameters, _nested_error} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: 1}},
                 %{action: "*:user", path: %{role: "3"}}
               ]
             })

    {:error, :bad_parameters, _nested_error1} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:user", path: %{role: 2, custom_path: "/user"}},
                 %{action: "*:admin", path: %{role: "2"}}
               ]
             })
  end

  test "Call sub_field struct with list attrs and validator, derive and main_validator" do
    {:error, :bad_parameters, _nested_error2} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1", rel: %{social: "github"}}},
                 %{action: "*:user", path: %{role: "3", rel: %{social: "github"}}}
               ],
               profile: [%{nickname: "mishka"}, %{nickname: "mishka1"}]
             })

    {:ok, _nested_struct} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1"}},
                 %{action: "*:user", path: %{role: "3", rel: %{social: "github"}}}
               ],
               profile: [%{github: "https://github.com/mishka-group"}]
             })
  end

  defmodule TestAutoValueStruct do
    use GuardedStruct

    guardedstruct do
      field(:username, String.t(), derive: "validate(not_empty)")
      field(:user_id, String.t(), auto: {Ecto.UUID, :generate})
      field(:parent_id, String.t(), auto: {Ecto.UUID, :generate})

      sub_field(:profile, struct()) do
        field(:id, String.t(), auto: {Ecto.UUID, :generate})
        field(:nickname, String.t(), derive: "validate(not_empty)")

        sub_field(:social, struct()) do
          field(:id, String.t(), auto: {TestAutoValueStruct, :create_uuid, "test-path"})
          field(:skype, String.t(), derive: "validate(string)")
          field(:username, String.t(), from: "root::username")
        end
      end

      sub_field(:items, struct(), structs: true) do
        field(:id, String.t(), auto: {Ecto.UUID, :generate})
        field(:something, String.t(), derive: "validate(string)", from: "root::username")
      end
    end

    def create_uuid(default) do
      Ecto.UUID.generate() <> "-#{default}"
    end
  end

  test "auto generate value nested and root map" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct{
       profile: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile{
         social: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile.Social{
           skype: "mishka_skype",
           id: social_UUID,
           username: "mishka"
         },
         nickname: "Mishka",
         id: profile_UUID
       },
       user_id: user_UUID,
       username: "mishka",
       parent_id: _parent_id
     }} =
      TestAutoValueStruct.builder(%{
        username: "mishka",
        user_id: "test_to_be_replaced",
        profile: %{nickname: "Mishka", social: %{skype: "mishka_skype", username: "none_to_test"}}
      })

    assert String.contains?(social_UUID, "test-path")

    assert ValidationDerive.validate(:uuid, profile_UUID, :test)
           |> is_binary()

    assert ValidationDerive.validate(:uuid, user_UUID, :test)
           |> is_binary()

    assert social_UUID != profile_UUID != user_UUID

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct{
       parent_id: _edit_parent_id,
       user_id: "test_not_to_be_replaced"
     }} =
      assert TestAutoValueStruct.builder(
               {:root,
                %{
                  username: "mishka",
                  user_id: "test_not_to_be_replaced"
                }, :edit}
             )
  end

  defmodule TestOnValueStruct do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), derive: "validate(string)")

      sub_field(:profile, struct()) do
        field(:id, String.t(), auto: {Ecto.UUID, :generate})
        field(:nickname, String.t(), on: "root::name", derive: "validate(string)")
        field(:github, String.t(), derive: "validate(string)")

        sub_field(:identity, struct()) do
          field(:provider, String.t(), on: "root::profile::github", derive: "validate(string)")
          field(:id, String.t(), auto: {Ecto.UUID, :generate})
          field(:rel, String.t(), on: "sub_identity::auth_path::action")

          sub_field(:sub_identity, struct()) do
            field(:id, String.t(), auto: {Ecto.UUID, :generate})
            field(:auth_path, struct(), struct: TestAuthStruct)
          end
        end
      end

      sub_field(:last_activity, list(struct()), structs: true) do
        field(:action, String.t(), enforce: true, derive: "validate(string)", on: "root::name")
      end
    end
  end

  test "call on value in a nested struct and extra module" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct{
       profile: %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct.Profile{
         identity: %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct.Profile.Identity{
           id: id1,
           provider: "git",
           sub_identity: %{id: _id}
         },
         github: "test",
         nickname: "Mishka",
         id: id2
       },
       name: "mishka"
     }} =
      assert TestOnValueStruct.builder(%{
               name: "mishka",
               profile: %{
                 nickname: "Mishka",
                 github: "test",
                 identity: %{
                   provider: "git",
                   sub_identity: %{id: "test", auth_path: %{action: "admin/edit"}}
                 }
               }
             })

    assert id1 != id2
    assert !is_nil(id1)
    assert !is_nil(id1)

    {:error, :bad_parameters,
     [
       %{
         field: :profile,
         errors:
           {:bad_parameters,
            [
              %{
                field: :identity,
                errors:
                  {:dependent_keys,
                   [%{message: _msg2, field: :rel}, %{message: _msg1, field: :provider}]}
              }
            ]}
       }
     ]} =
      assert TestOnValueStruct.builder(%{
               name: "mishka",
               profile: %{
                 nickname: "Mishka",
                 identity: %{provider: "git"}
               }
             })
  end

  test "check list struct depend on a key in another struct" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct{
       last_activity: [
         %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct.LastActivity{
           action: "login"
         },
         %MishkaDeveloperToolsTest.GuardedStructTest.TestOnValueStruct.LastActivity{
           action: "logout"
         }
       ],
       profile: nil,
       name: "mishka"
     }} =
      assert TestOnValueStruct.builder(%{
               name: "mishka",
               last_activity: [%{action: "login"}, %{action: "logout"}]
             })
  end

  test "call from value in a nested struct and extra module" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct{
       profile: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile{
         social: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile.Social{
           username: "user_mishka"
         }
       }
     }} =
      assert TestAutoValueStruct.builder(%{
               username: "user_mishka",
               user_id: "test_to_be_replaced",
               profile: %{
                 nickname: "Mishka",
                 social: %{skype: "mishka_skype", username: "none_to_test"}
               }
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct{
       profile: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile{
         social: %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Profile.Social{
           username: "user_mishka"
         }
       }
     }} =
      assert TestAutoValueStruct.builder(%{
               username: "user_mishka",
               user_id: "test_to_be_replaced",
               profile: %{nickname: "Mishka", social: %{skype: "mishka_skype"}}
             })
  end

  test "check list struct from a key in another struct" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct{
       items: [
         %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Items{
           something: "mishka",
           id: _
         },
         %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Items{
           something: "mishka",
           id: _
         },
         %MishkaDeveloperToolsTest.GuardedStructTest.TestAutoValueStruct.Items{
           something: "mishka",
           id: _
         }
       ],
       profile: nil,
       parent_id: _,
       user_id: _,
       username: "mishka"
     }} =
      assert TestAutoValueStruct.builder(%{
               username: "mishka",
               items: [
                 %{id: "test", something: "test"},
                 %{something: "test"},
                 %{}
               ]
             })
  end

  defmodule AllowedParentDomain do
    use GuardedStruct

    guardedstruct authorized_fields: true do
      field(:username, String.t(),
        domain: "!auth.action=String[admin, user]::?auth.social=Atom[banned]",
        derive: "validate(string)"
      )

      field(:type_social, String.t(),
        domain: "?auth.type=Map[%{name: \"mishka\"}, %{name: \"mishka2\"}]",
        derive: "validate(string)"
      )

      field(:social_equal, atom(),
        domain: "?auth.equal=Equal[Atom>>name]",
        derive: "validate(atom)"
      )

      field(:social_either, atom(),
        domain: "?auth.either=Either[string, enum>>Integer[1>>2>>3]]",
        derive: "validate(atom)"
      )

      sub_field(:auth, struct(), authorized_fields: true) do
        field(:action, String.t(), derive: "validate(not_empty)")
        field(:social, atom(), derive: "validate(atom)")
        field(:type, map(), derive: "validate(map)")
        field(:equal, atom(), derive: "validate(atom)")
        field(:either, atom())
      end
    end
  end

  test "domain parent and parameters domain core key" do
    {:error, :domain_parameters,
     [
       %{
         message: "Based on field username input you have to send authorized data",
         field: :username,
         field_path: "auth.action"
       }
     ]} =
      assert AllowedParentDomain.builder(%{username: "mishka", auth: %{action: "admin1"}})

    {:error, :domain_parameters,
     [
       %{
         message:
           "Based on field username input you have to send authorized data and required key",
         field: :username,
         field_path: "auth.action"
       }
     ]} =
      assert AllowedParentDomain.builder(%{username: "mishka", auth: %{action1: "admin"}})

    {:error, :domain_parameters, _} =
      assert AllowedParentDomain.builder(%{
               username: "mishka",
               auth: %{action: "admin", social: "test"}
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain.Auth{
         social: :banned,
         action: "admin"
       },
       username: "mishka"
     }} =
      assert AllowedParentDomain.builder(%{
               username: "mishka",
               auth: %{action: "admin", social: :banned}
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain.Auth{
         type: %{name: "mishka"},
         social: :banned,
         action: "admin"
       },
       type_social: "github",
       username: nil
     }} =
      assert AllowedParentDomain.builder(%{
               type_social: "github",
               auth: %{action: "admin", social: :banned, type: %{name: "mishka"}}
             })

    {:error, :domain_parameters,
     [
       %{
         message: "Based on field type_social input you have to send authorized data",
         field: :type_social,
         field_path: "auth.type"
       }
     ]} =
      assert AllowedParentDomain.builder(%{
               type_social: "github",
               auth: %{action: "admin", social: :banned, type: %{name: "test"}}
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain.Auth{
         equal: :name,
         type: nil,
         social: :banned,
         action: "admin"
       },
       social_equal: :github,
       type_social: nil,
       username: nil
     }} =
      assert AllowedParentDomain.builder(%{
               social_equal: :github,
               auth: %{action: "admin", social: :banned, equal: :name}
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain.Auth{
         either: "test",
         equal: nil,
         type: nil,
         social: :banned,
         action: "admin"
       },
       social_either: :github,
       social_equal: nil,
       type_social: nil,
       username: nil
     }} =
      assert AllowedParentDomain.builder(%{
               social_either: :github,
               auth: %{action: "admin", social: :banned, either: "test"}
             })

    {:error, :domain_parameters,
     [
       %{
         message: "Based on field social_either input you have to send authorized data",
         field: :social_either,
         field_path: "auth.either"
       }
     ]} =
      assert AllowedParentDomain.builder(%{
               social_either: :github,
               auth: %{action: "admin", social: :banned, either: 5}
             })

    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentDomain.Auth{
         either: 3,
         equal: nil,
         type: nil,
         social: :banned,
         action: "admin"
       },
       social_either: :github,
       social_equal: nil,
       type_social: nil,
       username: nil
     }} =
      assert AllowedParentDomain.builder(%{
               social_either: :github,
               auth: %{action: "admin", social: :banned, either: 3}
             })
  end

  defmodule AllowedParentCustomDomain do
    use GuardedStruct
    @module_path "MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentCustomDomain"

    guardedstruct authorized_fields: true do
      field(:username, String.t(),
        domain: "!auth.action=Custom[#{@module_path}, is_stuff?]",
        derive: "validate(string)"
      )

      sub_field(:auth, struct(), authorized_fields: true) do
        field(:action, String.t(), derive: "validate(not_empty)")
      end
    end

    def is_stuff?(data) when data == "ok", do: true
    def is_stuff?(_data), do: false
  end

  test "check Custom function inside domain core key" do
    {:ok,
     %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentCustomDomain{
       auth: %MishkaDeveloperToolsTest.GuardedStructTest.AllowedParentCustomDomain.Auth{
         action: "ok"
       },
       username: "mishka"
     }} =
      assert AllowedParentCustomDomain.builder(%{
               username: "mishka",
               auth: %{action: "ok"}
             })

    {:error, :domain_parameters,
     [
       %{
         message: "Based on field username input you have to send authorized data",
         field: :username,
         field_path: "auth.action"
       }
     ]} =
      assert AllowedParentCustomDomain.builder(%{
               username: "mishka",
               auth: %{action: "error"}
             })
  end

  defmodule ConditionalFieldTest do
    use GuardedStruct

    guardedstruct authorized_fields: true do
      field(:username, String.t(), derive: "validate(string, enum=String[shahryar::test])")

      conditional_field(:social, enforce: true) do
        field(:social, String.t(),
          derive: "validate(custom=[Kernel, is_binary])",
          validator: {__MODULE__, :social1}
        )

        field(:social, struct(),
          struct: TestAuthStruct,
          derive: "validate(custom=[Kernel, is_map])"
        )

        field(:social, list(struct()),
          structs: MishkaDeveloperToolsTest.GuardedStructDeriveTest,
          derive: "validate(custom=[Kernel, is_list])"
        )

        sub_field(:social, struct(), derive: "validate(custom=[#{__MODULE__}, is_social])") do
          field(:name, String.t())
        end

        sub_field(:social, struct(), derive: "validate(custom=[#{__MODULE__}, is_social])") do
          field(:name, String.t())
          field(:fam, String.t())
        end
      end
    end

    def validator(:username, value) do
      if is_binary(value), do: {:ok, :username, value}, else: {:error, :username, "No, never"}
    end

    def validator(field, value), do: {:ok, field, value}

    def is_social(%{name: "shahryar", fam: "tavakkoli"}),
      do: {:ok, %{social: %{name: "shahryar", fam: "tavakkoli"}}}

    def is_social(%{name: "shahryar"}), do: {:ok, %{social: %{name: "shahryar"}}}

    def is_social(_) do
      {:error, :bad_parameters,
       [
         %{
           message: "The social field must be integer",
           field: :social,
           action: :integer
         }
       ]}
    end

    def social1(field, value) do
      if is_binary(value), do: {:ok, field, value}, else: {:error, field, "No, never"}
    end
  end

  ############## (▰˘◡˘▰) GuardedStructTest Tests helper functions (▰˘◡˘▰) ##############
  # Extracts the first type from a module.
  defp types(bytecode) do
    bytecode
    |> Code.Typespec.fetch_types()
    |> elem(1)
    |> Enum.sort()
  end

  # Sample fields
  # [
  #   {:type, _, :map_field_exact, _},
  #   {:type, _, _, [{:atom, _, :int}, _]},
  #   {:type, _, _, [{:atom, _, :mandatory_int}, _]},
  #   {:type, _, _, [{:atom, _, :string}, _]},
  #   {:type, _, _, [{:atom, _, :string_with_default}, _]}
  # ]

  defp check_type(type, bytecode, fields, struct_type \\ :type)

  defp check_type(:t, bytecode, fields, :type) do
    [type: {:t, {:type, _, :map, list}, []}] = types(bytecode)

    all_allowed_fields_exist?(list, fields)
  end

  defp check_type(:t, bytecode, fields, :opaque) do
    [opaque: {:t, {:type, _, :map, list}, []}] = types(bytecode)

    all_allowed_fields_exist?(list, fields)
  end

  defp all_allowed_fields_exist?(list, fields) do
    get_fields =
      list
      |> Enum.filter(fn {:type, _, _, [{:atom, _, f}, _]} -> Enum.member?(fields, f) end)
      |> Enum.map(fn {:type, _, _, [{:atom, _, f}, _]} -> f end)
      |> Enum.sort()

    Enum.sort(fields) == get_fields
  end
end

# conditional_field(:social,
#   which: "String::Function(AllowedParentDomain, is_stuff?)::Struct[]::Struct"
# ) do
#   field(:social, String.t(), derive: "validate(not_empty)")
#   field(:social, struct(), struct: TestAuthStruct)
#   field(:social, list(struct()), structs: TestAuthStruct)

#   sub_field(:social, struct()) do
#     field(:name, String.t())
#   end
# end
