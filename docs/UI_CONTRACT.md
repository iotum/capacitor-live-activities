# Shared UI Contract v2

Rails selects content and ordered profiles; native code chooses layout and native
visual treatment. The `display` fields and profile selections are defined by
`LiveActivityDisplay` in the public TypeScript API. Unix-second timers are shared
across both transports. The call fixture exercises the wire contract.

## Styling Tokens

| Token | Native Treatment |
|---|---|
| `phase: ringing` | Gold `#F4C95D` accent |
| `phase: connected` | Green `#65D69A` accent |
| `phase: ended` | Neutral `#B8C0CC` accent |
| `header` | Lock-screen card heading / Android notification subtext |
| item `selected` | iOS tinted outline and accessibility trait / Android selected label |
| action `icon` | Semantic `record`, `ticket`, `note`, `open`, mapped to native resources |
| action `emphasis` | `primary`, `secondary`, `destructive`; defaults to secondary |

iOS primary buttons are filled, secondary buttons subdued, destructive buttons
red. Android uses system notification buttons: fills cannot be promised, icons
and accents may be suppressed by the OS. Destructive actions carry a semantic
hint; primary emphasis is represented by Rails' first action, never reordering
on the client. Omitted tokens use neutral defaults. Do not use phase colors to
invent CRM metric sentiment.

Release requires native builds and device/visual checks. TypeScript and fixture
validation on Linux are not substitutes for those checks.