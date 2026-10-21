# local_user_input_module が nil を返す場合のフォールバック検証用
defmodule Contents.ComponentListTest.NilReturningContent do
  def components, do: []
  def local_user_input_module, do: nil
end

# local_user_input_module をオーバーライドするコンテンツ（実装パス検証用）
defmodule Contents.ComponentListTest.CustomLocalUserContent do
  def components, do: []
  def local_user_input_module, do: Contents.LocalUserComponent
end

defmodule Contents.ComponentListTest do
  use ExUnit.Case, async: false

  describe "local_user_input_module/1" do
    test "local_user_input_module 未実装のコンテンツは Contents.LocalUserComponent を返す" do
      assert Contents.ComponentList.local_user_input_module(Content.BulletHell3D) ==
               Contents.LocalUserComponent
    end

    test "local_user_input_module 実装コンテンツはそのモジュールを返す" do
      content = Contents.ComponentListTest.CustomLocalUserContent
      expected = Contents.LocalUserComponent

      assert Contents.ComponentList.local_user_input_module(content) == expected
    end

    test "nil を返すコンテンツは Contents.LocalUserComponent を返す" do
      assert Contents.ComponentList.local_user_input_module(
               Contents.ComponentListTest.NilReturningContent
             ) == Contents.LocalUserComponent
    end
  end

  describe "components/0" do
    test "LocalUserComponent が components に含まれる" do
      components = Contents.ComponentList.components()
      content = Core.Config.current()
      mod = Contents.ComponentList.local_user_input_module(content)

      assert mod in components
    end
  end
end
