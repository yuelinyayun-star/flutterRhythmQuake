'use strict';

const fs = require('fs');

const OVERRIDDEN_PROCEDURES = [
  'リセット %b',
  '検出id_新規id追加 %s %b',
  '検出id3_点にIDを登録 %s %b',
];

class StopScript extends Error {}

function scratchNumber(value) {
  const number = Number(value);
  return Number.isNaN(number) ? 0 : number;
}

function toBoolean(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    return value !== '' && value !== '0' && value.toLowerCase() !== 'false';
  }
  return Boolean(value);
}

function isNotActuallyZero(value) {
  return typeof value === 'string' &&
    (value.length === 0 || !/^[-+]?0*(?:\.0*)?$/.test(value));
}

function compareValues(left, right, operation) {
  const leftNumber = Number(left);
  const rightNumber = Number(right);
  const numeric = !(Number.isNaN(leftNumber) || Number.isNaN(rightNumber)) &&
    !(leftNumber === 0 && isNotActuallyZero(left)) &&
    !(rightNumber === 0 && isNotActuallyZero(right));
  const a = numeric ? leftNumber : String(left).toLowerCase();
  const b = numeric ? rightNumber : String(right).toLowerCase();
  if (operation === 'lt') return a < b;
  if (operation === 'gt') return a > b;
  return a === b;
}

function listIndex(value, length) {
  if (value === 'last') return length;
  if (value === 'random' || value === 'any') return length > 0 ? 1 : 0;
  return Math.trunc(scratchNumber(value));
}

function listGet(list, index) {
  const resolved = listIndex(index, list.length);
  return resolved < 1 || resolved > list.length ? '' : (list[resolved - 1] ?? '');
}

function letterOf(value, index) {
  const text = String(value);
  const resolved = Math.trunc(scratchNumber(index));
  return resolved < 1 || resolved > text.length ? '' : text.charAt(resolved - 1);
}

function deepClone(value) {
  return Array.isArray(value) ? value.map((item) => deepClone(item)) : value;
}

function loadProject(projectPath) {
  const project = JSON.parse(fs.readFileSync(projectPath, 'utf8'));
  const stage = project.targets.find((target) => target.isStage);
  const receiver = project.targets.find((target) => target.name === '受信と検出');
  if (!stage || !receiver) {
    throw new Error('srev project must contain Stage and 受信と検出 targets');
  }
  return {project, stage, receiver};
}

function syncTargetVariables(runtimeTarget, projectTarget) {
  for (const [id, raw] of Object.entries(projectTarget.variables || {})) {
    const existing = runtimeTarget.variables[id];
    if (existing) {
      existing.name = raw[0];
      existing.value = deepClone(raw[1]);
    } else {
      runtimeTarget.variables[id] = {
        id,
        name: raw[0],
        type: '',
        value: deepClone(raw[1]),
      };
    }
  }
  for (const [id, raw] of Object.entries(projectTarget.lists || {})) {
    const existing = runtimeTarget.variables[id];
    if (existing) {
      existing.name = raw[0];
      existing.value = deepClone(raw[1]);
    } else {
      runtimeTarget.variables[id] = {
        id,
        name: raw[0],
        type: 'list',
        value: deepClone(raw[1]),
      };
    }
  }
}

function procedureDefinitions(receiver) {
  const blocks = receiver.blocks || {};
  const definitions = new Map();
  for (const definition of Object.values(blocks)) {
    if (definition.opcode !== 'procedures_definition') continue;
    const prototypeId = definition.inputs?.custom_block?.[1];
    const prototype = blocks[prototypeId];
    if (!prototype?.mutation?.proccode) continue;
    definitions.set(prototype.mutation.proccode, {
      bodyId: definition.next,
      argumentIds: JSON.parse(prototype.mutation.argumentids || '[]'),
      argumentNames: JSON.parse(prototype.mutation.argumentnames || '[]'),
    });
  }
  return definitions;
}

class ScratchOverrideInterpreter {
  constructor(thread, receiver) {
    this.thread = thread;
    this.blocks = receiver.blocks || {};
    this.definitions = procedureDefinitions(receiver);
    this.statementCount = 0;
    this.maxStatements = 5000000;
  }

  variable(field) {
    const id = field?.[1];
    const local = this.thread.target.variables[id];
    if (local) return local;
    const stage = this.thread.target.runtime.stage.variables[id];
    if (stage) return stage;
    throw new Error(`Scratch variable not found: ${JSON.stringify(field)}`);
  }

  literal(value) {
    if (!Array.isArray(value)) return value;
    const type = value[0];
    if (type === 12 || type === 13) return this.variable([value[1], value[2]]).value;
    return value[1];
  }

  input(block, name, env) {
    const value = block.inputs?.[name];
    if (!Array.isArray(value)) return '';
    if (typeof value[1] === 'string' && this.blocks[value[1]]) {
      return this.reporter(value[1], env);
    }
    if (Array.isArray(value[1])) return this.literal(value[1]);
    if (Array.isArray(value[2])) return this.literal(value[2]);
    return '';
  }

  reporter(blockId, env) {
    const block = this.blocks[blockId];
    if (!block) return '';
    const input = (name) => this.input(block, name, env);
    switch (block.opcode) {
      case 'argument_reporter_boolean':
      case 'argument_reporter_string_number':
        return env.get(block.fields?.VALUE?.[0]) ?? '';
      case 'data_itemoflist':
        return listGet(this.variable(block.fields.LIST).value, input('INDEX'));
      case 'data_itemnumoflist': {
        const list = this.variable(block.fields.LIST).value;
        const item = input('ITEM');
        const index = list.findIndex((value) => compareValues(value, item, 'eq'));
        return index < 0 ? 0 : index + 1;
      }
      case 'data_lengthoflist':
        return this.variable(block.fields.LIST).value.length;
      case 'data_listcontainsitem':
        return this.variable(block.fields.LIST).value.some((value) =>
          compareValues(value, input('ITEM'), 'eq')
        );
      case 'operator_add':
        return scratchNumber(input('NUM1')) + scratchNumber(input('NUM2'));
      case 'operator_subtract':
        return scratchNumber(input('NUM1')) - scratchNumber(input('NUM2'));
      case 'operator_multiply':
        return scratchNumber(input('NUM1')) * scratchNumber(input('NUM2'));
      case 'operator_divide':
        return scratchNumber(input('NUM1')) / scratchNumber(input('NUM2'));
      case 'operator_mod': {
        const divisor = scratchNumber(input('NUM2'));
        if (divisor === 0) return NaN;
        return ((scratchNumber(input('NUM1')) % divisor) + divisor) % divisor;
      }
      case 'operator_round':
        return Math.round(scratchNumber(input('NUM')));
      case 'operator_mathop':
        return this.mathOperation(block.fields.OPERATOR?.[0], input('NUM'));
      case 'operator_equals':
        return compareValues(input('OPERAND1'), input('OPERAND2'), 'eq');
      case 'operator_lt':
        return compareValues(input('OPERAND1'), input('OPERAND2'), 'lt');
      case 'operator_gt':
        return compareValues(input('OPERAND1'), input('OPERAND2'), 'gt');
      case 'operator_and':
        return toBoolean(input('OPERAND1')) && toBoolean(input('OPERAND2'));
      case 'operator_or':
        return toBoolean(input('OPERAND1')) || toBoolean(input('OPERAND2'));
      case 'operator_not':
        return !toBoolean(input('OPERAND'));
      case 'operator_join':
        return String(input('STRING1')) + String(input('STRING2'));
      case 'operator_letter_of':
        return letterOf(input('STRING'), input('LETTER'));
      case 'sensing_keyoptions':
        return block.fields?.KEY_OPTION?.[0] ?? 'any';
      case 'sensing_keypressed':
        return false;
      case 'alwaystimer_getTimer':
      case 'sensing_timer':
        return this.thread.__srevAlwaysTimerSeconds ?? 0;
      default:
        throw new Error(`Unsupported Scratch reporter opcode: ${block.opcode}`);
    }
  }

  mathOperation(operation, rawValue) {
    const value = scratchNumber(rawValue);
    switch (operation) {
      case 'abs': return Math.abs(value);
      case 'floor': return Math.floor(value);
      case 'ceiling': return Math.ceil(value);
      case 'sqrt': return Math.sqrt(value);
      case 'sin': return Math.sin(value * Math.PI / 180);
      case 'cos': return Math.cos(value * Math.PI / 180);
      case 'tan': return Math.tan(value * Math.PI / 180);
      case 'asin': return Math.asin(value) * 180 / Math.PI;
      case 'acos': return Math.acos(value) * 180 / Math.PI;
      case 'atan': return Math.atan(value) * 180 / Math.PI;
      case 'ln': return Math.log(value);
      case 'log': return Math.log10(value);
      case 'e ^': return Math.exp(value);
      case '10 ^': return 10 ** value;
      default: throw new Error(`Unsupported Scratch math operation: ${operation}`);
    }
  }

  runStack(blockId, env, prefix) {
    let currentId = blockId;
    while (currentId) {
      this.statementCount += 1;
      if (this.statementCount > this.maxStatements) {
        throw new Error('Scratch override statement guard exceeded');
      }
      const block = this.blocks[currentId];
      if (!block) throw new Error(`Scratch block not found: ${currentId}`);
      const input = (name) => this.input(block, name, env);
      switch (block.opcode) {
        case 'data_setvariableto':
          this.variable(block.fields.VARIABLE).value = input('VALUE');
          break;
        case 'data_changevariableby': {
          const variable = this.variable(block.fields.VARIABLE);
          variable.value = scratchNumber(variable.value) + scratchNumber(input('VALUE'));
          break;
        }
        case 'data_deletealloflist':
          this.variable(block.fields.LIST).value.length = 0;
          break;
        case 'data_addtolist':
          this.variable(block.fields.LIST).value.push(input('ITEM'));
          break;
        case 'data_replaceitemoflist': {
          const variable = this.variable(block.fields.LIST);
          const index = listIndex(input('INDEX'), variable.value.length);
          if (index >= 1 && index <= variable.value.length) {
            variable.value[index - 1] = input('ITEM');
          }
          break;
        }
        case 'control_if':
          if (toBoolean(input('CONDITION'))) {
            this.runStack(block.inputs?.SUBSTACK?.[1], env, prefix);
          }
          break;
        case 'control_if_else':
          this.runStack(
            toBoolean(input('CONDITION'))
              ? block.inputs?.SUBSTACK?.[1]
              : block.inputs?.SUBSTACK2?.[1],
            env,
            prefix
          );
          break;
        case 'control_repeat': {
          const count = Math.max(0, Math.round(scratchNumber(input('TIMES'))));
          for (let index = 0; index < count; index += 1) {
            this.runStack(block.inputs?.SUBSTACK?.[1], env, prefix);
          }
          break;
        }
        case 'control_repeat_until': {
          let guard = 0;
          while (!toBoolean(input('CONDITION'))) {
            this.runStack(block.inputs?.SUBSTACK?.[1], env, prefix);
            guard += 1;
            if (guard > 1000000) throw new Error('Scratch repeat-until guard exceeded');
          }
          break;
        }
        case 'control_stop':
          throw new StopScript();
        case 'procedures_call':
          this.callCompiled(block, env, prefix);
          break;
        default:
          throw new Error(`Unsupported Scratch statement opcode: ${block.opcode}`);
      }
      currentId = block.next;
    }
  }

  callCompiled(block, env, prefix) {
    const proccode = block.mutation?.proccode;
    if (proccode === '​​log​​ %s' || proccode === '​​breakpoint​​') return;
    const argumentIds = JSON.parse(block.mutation?.argumentids || '[]');
    const args = argumentIds.map((id) => this.input(block, id, env));
    const candidates = [`${prefix}${proccode}`, `W${proccode}`, `Z${proccode}`];
    const key = candidates.find((candidate) => this.thread.procedures[candidate]);
    if (!key) throw new Error(`Compiled Scratch procedure not found: ${proccode}`);
    runMaybeGenerator(this.thread.procedures[key](...args));
  }

  call(proccode, args, prefix) {
    const definition = this.definitions.get(proccode);
    if (!definition) throw new Error(`Scratch procedure definition not found: ${proccode}`);
    const env = new Map();
    for (let index = 0; index < definition.argumentNames.length; index += 1) {
      env.set(definition.argumentNames[index], args[index] ?? '');
    }
    this.statementCount = 0;
    try {
      this.runStack(definition.bodyId, env, prefix);
    } catch (error) {
      if (!(error instanceof StopScript)) throw error;
    }
  }
}

function runMaybeGenerator(value) {
  if (!value || typeof value.next !== 'function') return value;
  let result = value.next();
  let guard = 0;
  while (!result.done) {
    guard += 1;
    if (guard > 1000000) throw new Error('Compiled Scratch generator guard exceeded');
    result = value.next();
  }
  return result.value;
}

function installSrevKaizouOverrides(thread, projectPath) {
  const source = loadProject(projectPath);
  syncTargetVariables(thread.target.runtime.stage, source.stage);
  syncTargetVariables(thread.target, source.receiver);
  const interpreter = new ScratchOverrideInterpreter(thread, source.receiver);
  for (const proccode of OVERRIDDEN_PROCEDURES) {
    for (const prefix of ['W', 'Z']) {
      const key = `${prefix}${proccode}`;
      if (!thread.procedures[key]) continue;
      thread.procedures[key] = (...args) => interpreter.call(proccode, args, prefix);
    }
  }
  return {
    interpreter,
    project: source.project,
    stage: source.stage,
    receiver: source.receiver,
    overriddenProcedures: [...OVERRIDDEN_PROCEDURES],
  };
}

module.exports = {
  OVERRIDDEN_PROCEDURES,
  ScratchOverrideInterpreter,
  installSrevKaizouOverrides,
  syncTargetVariables,
};
