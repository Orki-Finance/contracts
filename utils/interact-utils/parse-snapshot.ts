
export interface ProtocolSnapshot {
    totalSupply: number;
    numberBranches: number;
    timestamp: number;
    block: number;
    branches: Branch[];
    protocolConfig: ProtocolConfig;
    owners: UserBalance[];
}

interface UserBalance {
    address: string;
    usdqBalance: number;
    collaterals: CollateralBalance[];
}

interface CollateralBalance {
    index: number;
    symbol: string;
    balance: number;
}

interface ActivePool {
    totalCollateral: number;
    boldDebt: number;
    lastAggUpdateTime: number;
}

interface DefaultPool {
    totalCollateral: number;
    boldDebt: number;
}

interface CollSurplusPool {
    totalSurplus: number;
}

interface StabilityPool {
    totalDeposits: number;
    yieldGainsPending: number;
    yieldGainsOwed: number;
    collBalance: number;
}

interface Branch {
    index: number;
    collateral: string;
    symbol: string;
    decimals: number;
    totalTroves: number;
    totalDebt: number;
    totalCollateral: number;
    TCR: number;
    totalSPDeposits: number;
    shutdownTime: number;
    CCR: number;
    MCR: number;
    SCR: number;
    liquidationPenaltySP: number;
    liquidationPenaltyRedistribution: number;
    minDebt: number;
    SPYieldSplit: number;
    minAnnualInterestRate: number;
    lastGoodPrice: number;
    troves: Trove[];
    activePool: ActivePool;
    defaultPool: DefaultPool;
    collSurplusPool: CollSurplusPool;
    stabilityPool: StabilityPool;
}

interface Trove {
    troveId: string;
    entireDebt: number;
    entireColl: number;
    status: string;
    ICR: number;
    annualInterestRate: number;
    owner: string;
}

interface ProtocolConfig {
    decimalPrecision: number;
    onePercent: number;
    oneHundredPercent: number;
    ethGasCompensation: number;
}

export function parseSnapshot(jsonString: string): ProtocolSnapshot {
    return JSON.parse(jsonString);
}
