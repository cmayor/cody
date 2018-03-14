require 'rails_helper'

RSpec.describe ReceiveIssueCommentEvent do
  let!(:pr) { FactoryBot.create :pull_request, status: "pending_review" }

  let(:reviewer) { "aergonaut" }

  let(:payload) do
    from_fixture = json_fixture("issue_comment")
    from_fixture["issue"]["number"] = pr.number
    from_fixture["sender"]["login"] = sender
    from_fixture["comment"]["body"] = comment
    from_fixture
  end

  let(:job) { ReceiveIssueCommentEvent.new }

  let(:sender) { reviewer }

  describe "#perform" do
    before do
      stub_request(:post, %r(https?://api.github.com/repos/\w+/\w+/statuses/[0-9abcdef]{40}))
      stub_request(:get, %r(https?://api.github.com/repos/\w+/\w+/pulls/\d+)).to_return(
        body: pr_response_body,
        status: 200,
        headers: { "Content-Type" => "application/json" }
      )
      stub_request(:patch, %r{https?://api.github.com/repos/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/issues/\d+})

      FactoryBot.create(:reviewer, login: reviewer, pull_request: pr)

      job.perform(payload)
    end

    context "when submitting an approval" do
      let(:comment) { "lgtm" }

      let(:pr_response_body) { File.open(Rails.root.join("spec", "fixtures", "pr.json")) }

      context "when the commenter is a reviewer" do
        context "and they approve" do
          it "moves them into the completed_reviews list" do
            pr.reload
            expect(pr.reviewers.pending_review.map(&:login)).to_not include(reviewer)
            expect(pr.reviewers.completed_review.map(&:login)).to include(sender)
          end

          context "and they are the last approver" do
            it "updates the status on GitHub" do
              expect(WebMock).to have_requested(:post, %r(https?://api.github.com/repos/\w+/\w+/statuses/[0-9abcdef]{40}))
            end

            it "marks the PR as approved" do
              expect(pr.reload.status).to eq("approved")
            end
          end

          context "and they approve with a literal emoji" do
            let(:comment) { "👍" }

            it "moves them into the completed_reviews list" do
              pr.reload
              expect(pr.reviewers.pending_review.map(&:login)).to_not include(reviewer)
              expect(pr.reviewers.completed_review.map(&:login)).to include(sender)
            end
          end
        end
      end
    end
  end

  describe "#comment_replace" do
    let(:comment) { "cody replace foo=BrentW bar=mrpasquini" }

    let(:rule) { FactoryBot.create :review_rule, short_code: "foo", reviewer: acceptable_reviewer }

    before do
      stub_request(:get, %r(https?://api.github.com/repos/\w+/\w+/pulls/\d+)).to_return(
        body: JSON.dump(json_fixture("pr")),
        status: 200,
        headers: { "Content-Type" => "application/json" }
      )
      stub_request(:patch, %r{https?://api.github.com/repos/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/pulls/\d+})
      stub_request(:patch, %r{https?://api.github.com/repos/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/issues/\d+})

      FactoryBot.create :reviewer, review_rule: rule, pull_request: pr, login: "aergonaut"
    end

    context "when BrentW is a possible reviewer for the rule" do
      let(:acceptable_reviewer) { "BrentW" }

      it "replaces aergonaut with BrentW" do
        foo_reviewer = pr.reviewers.find_by(review_rule_id: rule.id)
        expect { job.perform(payload) }.to change { foo_reviewer.reload.login }.from("aergonaut").to("BrentW")
      end
    end

    context "when BrentW is not a possible reviewer for the rule" do
      let(:acceptable_reviewer) { "octocat" }

      it "does not change the reviewer" do
        foo_reviewer = pr.reviewers.find_by(review_rule_id: rule.id)
        expect { job.perform(payload) }.to_not change { foo_reviewer.reload.login }
      end
    end
    
    context "when the reviewer is specified with an @ sign" do
      let(:comment) { "cody replace foo=@BrentW" }
      let(:acceptable_reviewer) { "BrentW" }
      
      it "replaces aergonaut with BrentW" do
        foo_reviewer = pr.reviewers.find_by(review_rule_id: rule.id)
        expect { job.perform(payload) }.to change { foo_reviewer.reload.login }.from("aergonaut").to("BrentW")
      end
    end
  end
  
  describe "#comment_replace_me" do
    let(:comment) { "cody replace me!" }

    let(:rule) { FactoryBot.create :review_rule, short_code: "foo", reviewer: acceptable_reviewer }

    before do
      stub_request(:get, %r(https?://api.github.com/repos/\w+/\w+/pulls/\d+)).to_return(
        body: JSON.dump(json_fixture("pr")),
        status: 200,
        headers: { "Content-Type" => "application/json" }
      )
      stub_request(:patch, %r{https?://api.github.com/repos/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/pulls/\d+})
      stub_request(:patch, %r{https?://api.github.com/repos/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/issues/\d+})

      FactoryBot.create :reviewer, review_rule: rule, pull_request: pr, login: "aergonaut"
    end

    context "when mrpasquini is a possible reviewer for the rule" do
      let(:acceptable_reviewer) { "mrpasquini" }

      it "replaces aergonaut with mrpasquini" do
        foo_reviewer = pr.reviewers.find_by(review_rule_id: rule.id)
        expect { job.perform(payload) }.to change { foo_reviewer.reload.login }.from("aergonaut").to("mrpasquini")
      end
    end

    context "when there is no other possible reviewer for the rule" do
      let(:acceptable_reviewer) { "aergonaut" }

      it "does not replace aergonaut" do
        foo_reviewer = pr.reviewers.find_by(review_rule_id: rule.id)
        expect { job.perform(payload) }.to_not change { foo_reviewer.reload.login }
      end
    end

  end

end
