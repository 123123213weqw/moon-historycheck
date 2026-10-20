# Source and design attribution

The domain implementation is written for this project with AI coding assistance. The JSON value boundary and CLI pattern are shared infrastructure from the author's October MoonBit projects and are not claimed as new domain algorithms.

Design references:

- [Porcupine](https://github.com/anishathalye/porcupine), MIT: executable sequential specifications, concurrent histories and witnesses. No Porcupine source or fixtures are copied into the library.
- [Faster linearizability checking via P-compositionality](https://arxiv.org/abs/1504.00204): independent-object decomposition is a known technique, not a new algorithm claimed here.
- [MoonRaft](https://github.com/moonbitstack/moonraft): related MoonBit distributed systems ecosystem. This project does not implement Raft and does not claim no related verification tools exist.

MoonBit core is a toolchain dependency. Python standard library and Node built-ins are used for independent reference checks, recorders and CLI tests. No runtime dependency on an external checker is required.
