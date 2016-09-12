require "spec_helper"

module Switchman
  module ActiveRecord
    describe QueryMethods do
      include RSpecHelper

      before do
        @user1 = User.create!
        @appendage1 = @user1.appendages.create!
        @user2 = @shard1.activate { User.create! }
        @appendage2 = @user2.appendages.create!
        @user3 = @shard2.activate { User.create! }
        @appendage3 = @user3.appendages.create!
      end

      describe "#primary_shard" do
        it "should be the shard if it's a shard" do
          expect(User.shard(Shard.default).primary_shard).to eq Shard.default
          expect(User.shard(@shard1).primary_shard).to eq @shard1
        end

        it "should be the first shard of an array of shards" do
          expect(User.shard([Shard.default, @shard1]).primary_shard).to eq Shard.default
          expect(User.shard([@shard1, Shard.default]).primary_shard).to eq @shard1
        end

        it "should be the object's shard if it's a model" do
          expect(User.shard(@user1).primary_shard).to eq Shard.default
          expect(User.shard(@user2).primary_shard).to eq @shard1
        end

        it "should be the default shard if it's a scope of Shard" do
          expect(User.shard(Shard.all).primary_shard).to eq Shard.default
          @shard1.activate do
            expect(User.shard(Shard.all).primary_shard).to eq Shard.default
          end
        end
      end

      it "should default to the current shard" do
        relation = User.all
        expect(relation.shard_value).to eq Shard.default
        expect(relation.shard_source_value).to eq :implicit

        @shard1.activate do
          expect(relation.shard_value).to eq Shard.default

          relation = User.all
          expect(relation.shard_value).to eq @shard1
          expect(relation.shard_source_value).to eq :implicit
        end
        expect(relation.shard_value).to eq @shard1
      end

      describe "with primary key conditions" do
        it "should be changeable, and change conditions when it is changed" do
          relation = User.where(:id => @user1).shard(@shard1)
          expect(relation.shard_value).to eq @shard1
          expect(relation.shard_source_value).to eq :explicit
          expect(where_value(predicates(relation).first.right)).to eq @user1.global_id
        end

        it "should infer the shard from a single argument" do
          relation = User.where(:id => @user2)
          # execute on @shard1, with id local to that shard
          expect(relation.shard_value).to eq @shard1
          expect(where_value(predicates(relation).first.right)).to eq @user2.local_id
        end

        it "should infer the shard from multiple arguments" do
          relation = User.where(:id => [@user2, @user2])
          # execute on @shard1, with id local to that shard
          expect(relation.shard_value).to eq @shard1
          expect(where_value(predicates(relation).first.right)).to eq [@user2.local_id, @user2.local_id]
        end

        it "does not die with an array of garbage executing on another shard" do
          relation = User.where(id: ['garbage', 'more_garbage'])
          expect(relation.shard([Shard.default, @shard1]).to_a).to eq []
        end

        it "doesn't munge a subquery" do
          relation = User.where(id: User.where(id: @user1))
          expect(relation.to_a).to eq [@user1]
        end

        it "should infer the correct shard from an array of 1" do
          relation = User.where(:id => [@user2])
          # execute on @shard1, with id local to that shard
          expect(relation.shard_value).to eq @shard1
          expect(where_value(Array(predicates(relation).first.right))).to eq [@user2.local_id]
        end

        it "should do nothing when it's an array of 0" do
          relation = User.where(:id => [])
          # execute on @shard1, with id local to that shard
          expect(relation.shard_value).to eq Shard.default
          expect(where_value(predicates(relation).first.right)).to eq []
        end

        it "should order the shards preferring the shard it already had as primary" do
          relation = User.where(:id => [@user1, @user2])
          expect(relation.shard_value).to eq [Shard.default, @shard1]
          expect(where_value(predicates(relation).first.right)).to eq [@user1.local_id, @user2.global_id]

          @shard1.activate do
            relation = User.where(:id => [@user1, @user2])
            expect(relation.shard_value).to eq [@shard1, Shard.default]
            expect(where_value(predicates(relation).first.right)).to eq [@user1.global_id, @user2.local_id]
          end
        end

        it "doesn't choke on valid objects with no id" do
          u = User.new
          User.where.not(id: u).shard([Shard.default, @shard1]).to_a
        end

        it "doesn't choke on NotEqual queries with valid objects on other shards" do
          u = User.create!
          User.where.not(id: u).shard([Shard.default, @shard1]).to_a
        end

        it "doesn't choke on non-integral primary keys that look like integers" do
          PageView.where(request_id: '123').take
        end

        it "transposes a global id to the shard the query will execute on" do
          u = @shard1.activate { User.create! }
          expect(User.shard(@shard1).where(id: u.id).take).to eq u
        end

        it "interprets a local id as relative to a relation's explicit shard" do
          u = @shard1.activate { User.create! }
          expect(User.shard(@shard1).where(id: u.local_id).take).to eq u
        end
      end

      describe "with foreign key conditions" do
        it "should be changeable, and change conditions when it is changed" do
          relation = Appendage.where(:user_id => @user1)
          expect(relation.shard_value).to eq Shard.default
          expect(relation.shard_source_value).to eq :implicit
          expect(where_value(predicates(relation).first.right)).to eq @user1.local_id

          relation = relation.shard(@shard1)
          expect(relation.shard_value).to eq @shard1
          expect(relation.shard_source_value).to eq :explicit
          expect(where_value(predicates(relation).first.right)).to eq @user1.global_id
        end

        it "should translate ids based on current shard" do
          relation = Appendage.where(:user_id => [@user1, @user2])
          expect(where_value(predicates(relation).first.right)).to eq [@user1.local_id, @user2.global_id]

          @shard1.activate do
            relation = Appendage.where(:user_id => [@user1, @user2])
            expect(where_value(predicates(relation).first.right)).to eq [@user1.global_id, @user2.local_id]
          end
        end

        it "should translate ids in joins" do
          relation = User.joins(:appendage).where(appendages: { user_id: [@user1, @user2]})
          expect(where_value(predicates(relation).first.right)).to eq [@user1.local_id, @user2.global_id]
        end

        it "should translate ids according to the current shard of the foreign type" do
          @shard1.activate(:mirror_universe) do
            mirror_user = MirrorUser.create!
            relation = User.where(mirror_user_id: mirror_user)
            expect(where_value(predicates(relation).first.right)).to eq mirror_user.global_id
          end
        end
      end

      describe "with table aliases" do
        it "should properly construct the query (at least in Rails 4)" do
          child = @user1.children.create!
          grandchild = child.children.create!
          expect(child.reload.parent).to eq @user1

          relation = @user1.association(:grandchildren).scope

          attribute = predicates(relation).first.left
          expect(attribute.name.to_s).to eq 'parent_id'
          unless ::Rails.version >= '5'
            # apparently rails 5 doesn't use table aliases here anymore
            expect(attribute.relation.class).to eq ::Arel::Nodes::TableAlias

            rel, column = relation.send(:relation_and_column, attribute)
            expect(relation.send(:sharded_primary_key?, rel, column)).to eq false
            expect(relation.send(:sharded_foreign_key?, rel, column)).to eq true
          end

          expect(@user1.grandchildren).to eq [grandchild]
        end
      end

      it "serializes subqueries relative to the relation's shard" do
        skip "can't detect which shard it serialized against" if Shard.default.name.include?(@shard1.name)
        User.connection.stubs(:use_qualified_names?).returns(true)
        sql = User.shard(@shard1).where("EXISTS (?)", User.all).to_sql
        expect(sql).not_to be_include(Shard.default.name)
        expect(sql.scan(@shard1.name).length).to eq 2
      end
    end
  end
end
