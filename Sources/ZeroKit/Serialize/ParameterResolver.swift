// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

// TODO: Move to a better location
public extension Dictionary where Key == String, Value == ZeroData {
    subscript(keyPath keyPath: String) -> ZeroData? {
        let comps = keyPath.split(separator: ".").map(String.init)
        return self[keyPath: comps]
    }

    subscript(keyPath comps: [String]) -> ZeroData? {
        if comps.isEmpty { return nil }
        else if comps.count == 1 { return self[comps[0]] }

        var comps = comps
        let key = comps.removeFirst()
        guard let val = self[key]?.dictionary else { return nil }
        return val[keyPath: comps]
    }
}

internal extension ParameterDeclaration {
    func `operator`() -> ZeroOperator? {
        guard case .parameter(let p) = self else { return nil }
        guard case .operator(let o) = p else { return nil }
        return o
    }
}

internal struct ParameterResolver {
    
    // MARK: - Internal Only
    
    let params: [ParameterDeclaration]
    let data: [String: ZeroData]
    let tags: [String: ZeroTag]
    let userInfo: [AnyHashable: Any]

    func resolve() throws -> [ResolvedParameter] {
        return try params.map(resolve)
    }

    internal struct ResolvedParameter {
        let param: ParameterDeclaration
        let result: ZeroData
    }
    
    // MARK: - Private Only

    private func resolve(_ param: ParameterDeclaration) throws -> ResolvedParameter {
        let result: ZeroData
        switch param {
            case .expression(let e):
                result = try resolve(expression: e)
            case .parameter(let p):
                result = try resolve(param: p)
            case .tag(let t):
                let resolver = ParameterResolver(
                    params: t.params,
                    data: self.data,
                    tags: self.tags,
                    userInfo: self.userInfo
                )
                let ctx = try ZeroContext(
                    parameters: resolver.resolve().map { $0.result },
                    data: data,
                    body: t.body,
                    userInfo: self.userInfo
                )
                result = try self.tags[t.name]?.render(ctx)
                    ?? .trueNil
        }
        return .init(param: param, result: result)
    }

    private func resolve(param: Parameter) throws -> ZeroData {
        switch param {
            case .constant(let c):
                switch c {
                    case .double(let d): return ZeroData(.double(d))
                    case .int(let d): return ZeroData(.int(d))
                }
            case .stringLiteral(let s):
                return .init(.string(s))
            case .variable(let v):
                return data[keyPath: v] ?? .trueNil
            case .keyword(let k):
                switch k {
                    case .self: return .init(.dictionary(data))
                    case .nil: return .trueNil
                    case .true, .yes: return .init(.bool(true))
                    case .false, .no: return .init(.bool(false))
                    default: throw "unexpected keyword"
                }
            // these should all have been removed in processing
            case .tag: throw "unexpected tag"
            case .operator: throw "unexpected operator"
        }
    }

    // #if(lowercase(first(name == "admin")) == "welcome")
    private func resolve(expression: [ParameterDeclaration]) throws -> ZeroData {
        if expression.count == 1 {
            return try resolve(expression[0]).result
        } else if expression.count == 2 {
            if let lho = expression[0].operator() {
                let rhs = try resolve(expression[1]).result
                return try resolve(op: lho, rhs: rhs)
            } else if let _ = expression[1].operator() {
                throw "right hand expressions not currently supported"
            } else {
                throw "two part expression expected to include at least one operator"
            }
        } else if expression.count == 3 {
            // file == name + ".jpg"
            // should resolve to:
            // param(file) == expression(name + ".jpg")
            // based on priorities in such a way that each expression
            // is 3 variables, lhs, functor, rhs
            guard expression.count == 3 else { throw "multiple expressions not currently supported: \(expression)" }
            let lhs = try resolve(expression[0]).result
            let functor = expression[1]
            let rhs = try resolve(expression[2]).result
            guard case .parameter(let p) = functor else { throw "expected keyword or operator" }
            switch p {
                case .keyword(let k):
                    return try resolve(lhs: lhs, key: k, rhs: rhs)
                case .operator(let o):
                    return try resolve(lhs: lhs, op: o, rhs: rhs)
                default:
                    throw "unexpected parameter: \(p)"
            }
        } else {
            throw "unsupported expression, expected 2 or 3 components: \(expression)"
        }
    }

    private func resolve(op: ZeroOperator, rhs: ZeroData) throws -> ZeroData {
        switch op {
            case .not:
                let result = rhs.bool ?? !rhs.isNil
                return .bool(!result)
            case .minus:
                return try resolve(lhs: -1, op: .multiply, rhs: rhs)
            default:
                throw "unexpected left hand operator not supported: \(op)"
        }
    }

    private func resolve(lhs: ZeroData, op: ZeroOperator, rhs: ZeroData) throws -> ZeroData {
        switch op {
            case .not:
                throw "single expression operator"
            case .and:
                let lhs = lhs.bool ?? !lhs.isNil
                let rhs = rhs.bool ?? !rhs.isNil
                return .bool(lhs && rhs)
            case .or:
                let lhs = lhs.bool ?? !lhs.isNil
                let rhs = rhs.bool ?? !rhs.isNil
                return .bool(lhs || rhs)
            case .equal:
                return .bool(lhs == rhs)
            case .unequal:
                return .bool(lhs != rhs)
            case .lesser:
                guard let lhs = lhs.string, let rhs = rhs.string else { return ZeroData.trueNil }
                if let lhs = Double(lhs), let rhs = Double(rhs) {
                    return .bool(lhs < rhs)
                } else {
                    return .bool(lhs < rhs)
                }
            case .lesserOrEqual:
                guard let lhs = lhs.string, let rhs = rhs.string else { return ZeroData.trueNil }
                if let lhs = Double(lhs), let rhs = Double(rhs) {
                    return .bool(lhs <= rhs)
                } else {
                    return .bool(lhs <= rhs)
                }
            case .greater:
                guard let lhs = lhs.string, let rhs = rhs.string else { return ZeroData.trueNil }
                if let lhs = Double(lhs), let rhs = Double(rhs) {
                    return .bool(lhs > rhs)
                } else {
                    return .bool(lhs > rhs)
                }
            case .greaterOrEqual:
                guard let lhs = lhs.string, let rhs = rhs.string else { return ZeroData.trueNil }
                if let lhs = Double(lhs), let rhs = Double(rhs) {
                    return .init(.bool(lhs >= rhs))
                } else {
                    return .init(.bool(lhs >= rhs))
                }
            case .plus:
                return try plus(lhs: lhs, rhs: rhs)
            case .minus:
                return try minus(lhs: lhs, rhs: rhs)
            case .multiply:
                return try multiply(lhs: lhs, rhs: rhs)
            case .divide:
                return try divide(lhs: lhs, rhs: rhs)
            case .assignment: throw "Future feature"
            case .nilCoalesce: throw "Future feature"
            case .modulo: throw "Future feature"
            case .evaluate: throw "Future feature"
            case .scopeRoot: throw "Future feature"
            case .scopeMember: throw "Future feature"
            case .subOpen: throw "Future feature"
            case .subClose: throw "Future feature"
        }
    }

    private func plus(lhs: ZeroData, rhs: ZeroData) throws -> ZeroData {
        switch lhs.storage {
            case .array(let arr):
                let rhs = rhs.array ?? []
                return .array(arr + rhs)
            case .data(let data):
                let rhs = rhs.data ?? Data()
                return .data(data + rhs)
            case .string(let s):
                let rhs = rhs.string ?? ""
                return .string(s + rhs)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.storage {
                    let sum = Double(i) + d
                    return .double(sum)
                } else {
                    let rhs = rhs.int ?? 0
                    let added = i.addingReportingOverflow(rhs)
                    guard !added.overflow else { throw "Integer overflow" }
                    return .int(added.partialValue)
                }
            case .double(let d):
                let rhs = rhs.double ?? 0
                return .double(d + rhs)
            case .lazy(let load, _, _):
                let l = load()
                return try plus(lhs: l, rhs: rhs)
            case .dictionary(let lhs):
                var rhs = rhs.dictionary ?? [:]
                lhs.forEach { key, val in
                    rhs[key] = val
                }
                return .init(.dictionary(rhs))
                
            case .optional(_, _): throw "Optional unwrapping not possible yet"
            case .bool(let b):
                throw "unable to concatenate bool `\(b)` with `\(rhs)', maybe you meant &&"
        }
    }

    private func minus(lhs: ZeroData, rhs: ZeroData) throws -> ZeroData {
        switch lhs.storage {
            case .optional(_, _): throw "Optional unwrapping not possible yet"
            case .array(let arr):
                let rhs = rhs.array ?? []
                let new = arr.filter { !rhs.contains($0) }
                return .array(new)
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.storage {
                    let oppositeOfSum = Double(i) - d
                    return .double(oppositeOfSum)
                } else {
                    let rhs = rhs.int ?? 0
                    let subtracted = i.subtractingReportingOverflow(rhs)
                    guard !subtracted.overflow else { throw "Integer underflow" }
                    return .int(subtracted.partialValue)
                }
            case .double(let d):
                let rhs = rhs.double ?? 0
                return .double(d - rhs)
            case .lazy(let load, _, _):
                let l = load()
                return try minus(lhs: l, rhs: rhs)
            case .data, .string, .dictionary, .bool:
                throw "unable to subtract from \(lhs)"
        }
    }

    private func multiply(lhs: ZeroData, rhs: ZeroData) throws -> ZeroData {
        switch lhs.storage {
            case .optional(_, _): throw "Optional unwrapping not possible yet"
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.storage {
                    let product = Double(i) * d
                    return .double(product)
                } else {
                    let rhs = rhs.int ?? 0
                    return .int(i * rhs)
                }
            case .double(let d):
                let rhs = rhs.double ?? 0
                return .double(d * rhs)
            case .lazy(let load, _, _):
                let l = load()
                return try multiply(lhs: l, rhs: rhs)
            case .data, .array, .string, .dictionary, .bool:
                throw "unable to multiply this type `\(lhs)`"
        }
    }

    private func divide(lhs: ZeroData, rhs: ZeroData) throws -> ZeroData {
        switch lhs.storage {
            case .optional(_, _): throw "Optional unwrapping not possible yet"
            case .int(let i):
                // if either is double, be double
                if case .double(let d) = rhs.storage {
                    let product = Double(i) / d
                    return .double(product)
                } else {
                    let rhs = rhs.int ?? 0
                    return .int(i / rhs)
                }
            case .double(let d):
                let rhs = rhs.double ?? 0
                return .double(d / rhs)
            case .lazy(let load, _, _):
                let l = load()
                return try divide(lhs: l, rhs: rhs)
            case .data, .array, .string, .dictionary, .bool:
                throw "unable to multiply this type `\(lhs)`"
        }
    }

    private func resolve(lhs: ZeroData, key: ZeroKeyword, rhs: ZeroData) throws -> ZeroData {
        switch key {
            case .in:
                let arr = rhs.array ?? []
                return .init(.bool(arr.contains(lhs)))
            default:
                return .trueNil
        }
    }
}