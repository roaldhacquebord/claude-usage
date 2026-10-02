enum Fixtures {
    /// Real `/usage` output from Claude Code 2.1.269 on 2026-09-11, cut short after the
    /// start of the contributions section (which also contains `%` and `·`, and must be ignored).
    static let usageOutput = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 42% used · resets Sep 12 at 12am (Europe/Amsterdam)
    Current week (all models): 62% used · resets Sep 13 at 9pm (Europe/Amsterdam)
    Current week (Fable): 93% used · resets Sep 13 at 9pm (Europe/Amsterdam)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices or claude.ai.

    Last 24h · 1010 requests · 19 sessions
      47% of your usage was at >150k context
      19% of your usage came from subagent-heavy sessions
    """

    /// Real `/usage` output from Claude Code 2.1.287 on 2026-10-02, when it couldn't get the limits
    /// from the server: the header and contributions section are there, the limit lines are not.
    static let usageOutputWithoutLimits = """
    You are currently using your subscription to power your Claude Code usage

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

    Last 24h · 1058 requests · 10 sessions
      62% of your usage was at >150k context
      56% of your usage came from subagent-heavy sessions
    """
}
