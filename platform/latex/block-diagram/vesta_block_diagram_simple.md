# VESTA RV32IMAC Core - Block Diagram (Mermaid)

This is a simpler alternative that can be rendered in GitHub, VS Code, or Mermaid Live Editor.

## High-Level Architecture

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#4682B4', 'primaryTextColor': '#fff', 'primaryBorderColor': '#2F4F4F', 'lineColor': '#5F5F5F', 'secondaryColor': '#FF8C42', 'tertiaryColor': '#64B464'}}}%%
flowchart TB
    subgraph VESTA["🔷 VESTA RV32IMAC Core"]
        direction TB
        
        subgraph FETCH["Instruction Fetch"]
            PC["📍 Program Counter"]
            CDEC["🔄 C_DEC<br/><i>RVC Decoder</i>"]
        end
        
        subgraph CONTROL["Control Unit"]
            CTRL["🎛️ Controller"]
            MDEC["Main Dec"]
            ADEC["ALU Dec"]
            BV["Branch Valid"]
        end
        
        subgraph EXECUTE["Datapath"]
            DP["⚡ Datapath"]
            RF["Register File<br/><i>32 x 32-bit</i>"]
            ALU["ALU"]
            DIV["Divider"]
            EXT["Extend"]
            LE["Load Ext"]
            SE["Store Ext"]
        end
        
        subgraph SYSTEM["System"]
            CSR["📊 CSR Unit<br/><i>Status Registers</i>"]
            IRQ["🚨 IRQ Handler<br/><i>Priority & Nesting</i>"]
        end
    end
    
    %% External interfaces
    IMEM["📖 Instruction<br/>Memory"]
    DMEM["💾 Data<br/>Memory"]
    IRQVEC["⚡ IRQ<br/>Vector"]
    CLKRST["🕐 CLK/RST"]
    
    %% Connections
    CLKRST --> VESTA
    
    PC --> |"addr"| IMEM
    IMEM --> |"instr"| CDEC
    CDEC --> |"decoded"| CTRL
    
    CTRL --> |"control signals"| DP
    DP --> |"pc_target"| PC
    
    DP <--> |"data"| DMEM
    DP <--> |"csr read/write"| CSR
    
    IRQ --> |"irq_ctrl"| CTRL
    IRQ --> |"ivt_entry"| PC
    IRQVEC --> IRQ
    
    %% Submodule connections (simplified)
    CTRL --- MDEC
    CTRL --- ADEC
    CTRL --- BV
    
    DP --- RF
    DP --- ALU
    DP --- DIV
    DP --- EXT
    DP --- LE
    DP --- SE
```

## Data Flow Diagram

```mermaid
%%{init: {'theme': 'base'}}%%
flowchart LR
    subgraph Input
        I1["Instruction"]
        I2["Read Data"]
        I3["IRQ Signals"]
    end
    
    subgraph Processing
        P1["Decode"]
        P2["Execute"]
        P3["Memory Access"]
        P4["Write Back"]
    end
    
    subgraph Output
        O1["Address"]
        O2["Write Data"]
        O3["Control"]
    end
    
    I1 --> P1 --> P2 --> P3 --> P4
    I2 --> P3
    I3 --> P1
    P2 --> O1
    P3 --> O2
    P4 --> O3
```

## State Machine Overview

```mermaid
stateDiagram-v2
    [*] --> EXECUTE : reset
    
    EXECUTE --> MEMORY_WAIT : load/store
    EXECUTE --> DIV_WAIT : division
    EXECUTE --> IRQ_SV : interrupt
    EXECUTE --> AMO_READ : atomic op
    EXECUTE --> SLEEPING : sleep
    
    MEMORY_WAIT --> EXECUTE : done
    
    DIV_WAIT --> DIV_DONE : complete
    DIV_DONE --> EXECUTE
    
    IRQ_SV --> IRQ_JUMP : context saved
    IRQ_JUMP --> EXECUTE : jump to ISR
    
    EXECUTE --> IRQ_REST : isr_ret
    IRQ_REST --> EXECUTE : restored
    
    AMO_READ --> AMO_COMPUTE : read done
    AMO_COMPUTE --> AMO_WRITE : compute done
    AMO_WRITE --> EXECUTE : write done
    
    SLEEPING --> EXECUTE : wake/irq
```

## ISA Extensions

| Extension | Full Name | Description |
|:---------:|-----------|-------------|
| **I** | Base Integer | Load, store, arithmetic, branches |
| **M** | Multiply | MUL, MULH, DIV, REM |
| **A** | Atomic | LR, SC, AMO operations |
| **C** | Compressed | 16-bit instruction encoding |
| **Zicsr** | CSR | Control/Status Registers |

---

*Render this file with any Mermaid-compatible viewer*
