# Drops Xcode diagnostic blocks that come from Swift Package Manager dependency
# sources, so the build result is not buried under hundreds of deprecation
# warnings. Errors always survive: a block can only be opened by a `warning:`
# header, and any line that is not part of the rendered block closes it.
#
#   <path>/ephemeral/Packages/....h:14:40: warning: 'SKProduct' is deprecated:
#     15 | @interface FIAPaymentQueueHandler
#        |                 `- warning: ... is deprecated
#        :
#
# Only headers whose path is inside Flutter's ephemeral SPM checkout are
# suppressed. Warnings from the pub cache and the project itself are kept.

BEGIN { block = 0 }

# A warning header for a file inside the ephemeral SPM checkout opens a block.
/\/ephemeral\/Packages\/.*:[0-9]+:[0-9]+: warning:/ { block = 1; next }

block && /^[[:space:]]*[0-9]+ \|/ && !/error:/ { next }  # source line
block && /^[[:space:]]*\|/ && !/error:/        { next }  # caret/note/`- warning:
block && /^[[:space:]]*:/                      { next }  # elided source
block && /^[[:space:]]*$/                      { next }  # separator between diagnostics

{ block = 0; print }
