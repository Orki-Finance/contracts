import * as fs from 'fs';
import { ProtocolSnapshot, parseSnapshot } from './parse-snapshot';
import { ACTORS_LIST } from './actors';

const bold = (text: string) => `\x1b[1m${text}\x1b[22m`;
const italic = (text: string) => `\x1b[3m${text}\x1b[23m`;
const underline = (text: string) => `\x1b[4m${text}\x1b[24m`;
const cyan = (text: string) => `\x1b[36m${text}\x1b[39m`;
const yellow = (text: string) => `\x1b[33m${text}\x1b[39m`;
const green = (text: string) => `\x1b[32m${text}\x1b[39m`;
const red = (text: string) => `\x1b[31m${text}\x1b[39m`;

const stripAnsi = (str: string): string => {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
};

const padText = (text: string, width: number): string => {
  const strippedText = stripAnsi(text); // Remove ANSI codes for width calculation
  const paddedText = strippedText.padEnd(width); // Pad based on the stripped text length

  const apt = text.replace(strippedText, paddedText);
  return apt;
};

const generateTable = (headers: string[], rows: string[][]): string => {
  const colWidths = headers.map((_, colIndex) =>
    Math.max(
      ...rows.map(row => stripAnsi(row[colIndex]).length),  
      stripAnsi(headers[colIndex]).length
    )
  );

  let table = headers.map((header, i) => padText(header, colWidths[i])).join("  ") + "\n";

  rows.forEach(row => {
    table += row.map((cell, i) => padText(cell, colWidths[i])).join("  ") + "\n";
  });

  return table;
};

const formattedTCR = (tcr: number, decimalPrecision: number, ccr: number): string => {
  const tcrValue = tcr / decimalPrecision;
  const ccrValue = ccr / decimalPrecision;
  if (tcrValue > 100) {
    return "N/A";
  } else if (tcrValue < ccrValue) {
    return red(tcrValue.toFixed(2).toString());
  } else {
    return green(tcrValue.toFixed(2).toString());
  }
};

const formattedICR = (icr: number, decimalPrecision: number, mcr: number): string => {
  const icrValue = icr / decimalPrecision;
  const mcrValue = mcr / decimalPrecision;
  if (icrValue > 100) {
    return "N/A";
  } else if (icrValue < mcrValue) {
    return red(icrValue.toFixed(2).toString());
  } else {
    return green(icrValue.toFixed(2).toString());
  }
}

const generateAnsi = (data: ProtocolSnapshot): string => {

  let ansiOutput = `${bold("Protocol Snapshot Report")}\n\n`;

  ansiOutput += `  ${bold("Total Supply:       ")} ${green((data.totalSupply / data.protocolConfig.decimalPrecision).toFixed(2))} USDQ\n`;
  ansiOutput += `  ${bold("Number of Branches: ")} ${yellow(data.numberBranches.toString())}\n`;
  ansiOutput += `  ${bold("Timestamp:          ")} ${data.timestamp}\n`;
  ansiOutput += `  ${bold("Block Number:       ")} ${data.block}\n\n`;

  ansiOutput += `  ${underline("Overview")}\n\n`;

  const headers = [
    bold("    #"),
    bold("Collateral"),
    bold("Total Troves"),
    bold("Total Debt (USDQ)"),
    bold("Total Collateral"),
    bold("TCR"),
    bold("Price (USD)"),
    bold("SP Deposits"),
  ];

  // Rows for the overview table
  const rows = data.branches.map((branch) => {
    return [
      "    " + branch.index.toString(),
      cyan(branch.symbol),
      branch.totalTroves.toString(),
      (branch.totalDebt / data.protocolConfig.decimalPrecision).toFixed(2),
      (branch.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      formattedTCR(branch.TCR, data.protocolConfig.decimalPrecision, branch.CCR),
      (branch.lastGoodPrice / data.protocolConfig.decimalPrecision).toFixed(2),
      (branch.stabilityPool.totalDeposits / data.protocolConfig.decimalPrecision).toFixed(2),
    ];
  });

  ansiOutput += generateTable(headers, rows);

  data.branches.forEach((branch) => {
    ansiOutput += `\n${underline(bold(`Branch ${branch.index}: ${branch.collateral} (${branch.symbol})`))}\n\n`;

    ansiOutput += `  ${underline("Overall")}\n\n`;
    ansiOutput += `  ${bold("Total Troves:     ")} ${branch.totalTroves}\n`;
    ansiOutput += `  ${bold("Total Debt:       ")} ${green((branch.totalDebt / data.protocolConfig.decimalPrecision).toFixed(2))} USDQ\n`;
    ansiOutput += `  ${bold("Total Collateral: ")} ${yellow((branch.totalCollateral / (10 ** branch.decimals)).toFixed(2))} ${branch.symbol}\n`;
    ansiOutput += `  ${bold("TCR:              ")} ${formattedTCR(branch.TCR, data.protocolConfig.decimalPrecision, branch.CCR)}\n`;
    ansiOutput += `  ${bold("Shutdown Time:    ")} ${branch.shutdownTime}\n`;
    ansiOutput += `  ${bold("Last Good Price:  ")} ${(branch.lastGoodPrice / data.protocolConfig.decimalPrecision).toFixed(2)} USD\n`;

    ansiOutput += `\n\n  ${underline("Pools")}\n\n`;

    const poolHeaders = [
      bold("    ActivePool"),
      "", //valueCollumn
      bold("DefaultPool"),
      "", //valueCollumn
      bold("CollSurplusPool"),
      "", //valueCollumn
      bold("StabilityPool"),
      "", //valueCollumn
    ];

    const poolRows: string[][] = [];

    poolRows.push([ "", "", "", "", "", "", "", "", ]);

    poolRows.push([
      italic("    Collateral"),
      (branch.activePool.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      italic("Collateral"),
      (branch.defaultPool.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      italic("Collateral"),
      (branch.collSurplusPool.totalSurplus / data.protocolConfig.decimalPrecision).toFixed(2),
      italic("Collateral"),
      (branch.stabilityPool.collBalance / (10 ** branch.decimals)).toFixed(2),
    ]);

    poolRows.push([
      italic("    Debt"),
      (branch.activePool.boldDebt / data.protocolConfig.decimalPrecision).toFixed(2),
      italic("Debt"),
      (branch.defaultPool.boldDebt / data.protocolConfig.decimalPrecision).toFixed(2),
      "", "", 
      italic("Deposits"),
      (branch.stabilityPool.totalDeposits / data.protocolConfig.decimalPrecision).toFixed(2),
    ]);

    poolRows.push([
      "", "", "", "", "", "", 
      italic("Yield Gains Owed"),
      (branch.stabilityPool.yieldGainsOwed / data.protocolConfig.decimalPrecision).toFixed(2),
    ]);

    poolRows.push([
      "", "", "", "", "", "", 
      italic("Yield Gains Pending"),
      (branch.stabilityPool.yieldGainsPending / data.protocolConfig.decimalPrecision).toFixed(2),
    ]);

    ansiOutput += generateTable(poolHeaders, poolRows);

    // Troves List
    ansiOutput += `\n  ${bold("Troves List")}\n\n`;

    if (branch.troves.length > 0) {
      const troveTableHeaders = [
        bold("  Trove ID"),
        bold("Owner"),
        bold("Debt (USDQ)"),
        bold("Coll (" + branch.symbol + ")"),
        bold("Status"),
        bold("ICR"),
        bold("AIR (%)")
      ];
      const rows = branch.troves.map((trove) => {
        const troveIdReduced = trove.troveId.toString().slice(0, 8);
        return [
          cyan("  " + troveIdReduced),
          cyan(trove.owner),
          (trove.entireDebt / data.protocolConfig.decimalPrecision).toFixed(2),
          (trove.entireColl / (10 ** branch.decimals)).toFixed(2),
          trove.status,
          formattedICR(trove.ICR, data.protocolConfig.decimalPrecision, branch.MCR),
          (trove.annualInterestRate / data.protocolConfig.oneHundredPercent).toFixed(2),
        ];
      });

      ansiOutput += generateTable(troveTableHeaders, rows);
    } else {
      ansiOutput += `  ${italic(red("No troves available."))}\n`;
    }
  });

  if(data.owners.length > 0) {
    ansiOutput += `\n${underline(bold("Owners Balances"))}\n\n`;

    const ownerTableHeaders = [
      bold("  Owner"),
      bold("Alias"),
      bold("USDQ")
    ];

    for (let i = 0; i < data.branches.length; i++) {
      ownerTableHeaders.push(bold(`${data.branches[i].symbol}`));
    }

    const rows = data.owners.map((owner) => {
      let row = [
        cyan("  " + owner.address),
        ACTORS_LIST.find(actor => actor.address.toLowerCase() === owner.address.toLowerCase())?.name || "unknown",
        (owner.usdqBalance / data.protocolConfig.decimalPrecision).toFixed(2),
      ];

      for (let i = 0; i < data.branches.length; i++) {
        const collat = owner.collaterals.find(collateral => collateral.index === i);
        row.push(collat ? (collat.balance / (10 ** data.branches[i].decimals)).toFixed(2) : "N/A");
      }
      return row;
    });

    ansiOutput += generateTable(ownerTableHeaders, rows);
  }

  ansiOutput += `\n${underline(bold("Liquidatable troves IDs"))}\n\n`;

  const liquidatableHeaders = [
    bold("  Id"),
    bold("Trove ID"),
    bold("ICR")
  ];

  const liquidatableRows: string[][] = [];

  data.branches.forEach((branch) => {
    const MCR = branch.MCR / data.protocolConfig.decimalPrecision;
    branch.troves.forEach((trove) => {
      const ICR = trove.ICR / data.protocolConfig.decimalPrecision;
      if (ICR < MCR) {
        // ansiOutput += `${branch.index} - ${BigInt(trove.troveId).toString()} - ${ICR.toFixed(2)}\n`;
        liquidatableRows.push([
          "  " + branch.index.toString(),
          BigInt(trove.troveId).toString(),
          ICR.toFixed(2)
        ]);
      }
    });
  });

  if(liquidatableRows.length === 0) {
    ansiOutput += `  ${italic(red("No liquidatable troves."))}\n`;
  } else {
    ansiOutput += generateTable(liquidatableHeaders, liquidatableRows);
  }

  return ansiOutput;
}

const generateAnsiDiff = (oldData: ProtocolSnapshot, newData: ProtocolSnapshot): string => {
  let ansiOutput = `${bold("Protocol Diff Report")}\n\n`;

  const diffTotalSupply = (newData.totalSupply - oldData.totalSupply) / newData.protocolConfig.decimalPrecision;
  const diffNumberBranches = newData.numberBranches - oldData.numberBranches;
  const diffTimestamp = newData.timestamp - oldData.timestamp;
  const diffBlock = newData.block - oldData.block;

  ansiOutput += `  ${bold("Total Supply:       ")} ${(newData.totalSupply / newData.protocolConfig.decimalPrecision).toFixed(2)} USDQ `;
  if(diffTotalSupply !== 0) {
    ansiOutput += `(${diffTotalSupply > 0 ? green(`+${diffTotalSupply.toFixed(2)}`) : red(diffTotalSupply.toFixed(2))} USDQ${bold(")")}`;
  }
  ansiOutput += `${bold("\n  Number of Branches: ")} ${yellow(newData.numberBranches.toString())} `;
  if(diffNumberBranches !== 0) {
    ansiOutput += `(${diffNumberBranches > 0 ? green(`+${diffNumberBranches}`) : red(`-${diffNumberBranches}`)})`;
  }
  ansiOutput += `${bold("\n  Timestamp:          ")} ${newData.timestamp} `;
  if(diffTimestamp !== 0) {
    ansiOutput += `(time moved forward by ${cyan(diffTimestamp.toString())} seconds)`;
  }
  ansiOutput += `${bold("\n  Block Number:       ")} ${newData.block} `;
  if(diffBlock !== 0) {
    ansiOutput += `(block moved forward by ${cyan(diffBlock.toString())})`;
  }

  ansiOutput += `\n\n  ${underline("Overview")}\n\n`;

  const headers = [
    bold("  #"),
    bold("Collateral"),
    bold("Total Troves"),
    "", //diffTotalTroves
    bold("Debt (USDQ)"),
    "", //diffTotalDebt
    bold("Collateral"),
    "", //diffTotalCollateral
    bold("TCR"),
    "", //
    bold("Price (USD)"),
    "", //
    bold("SP Deposits"),
  ];

  const rows = newData.branches.map((branch) => {

    const oldBranch = oldData.branches.find((oldBranch) => oldBranch.index === branch.index);
    const diffTotalTroves = branch.totalTroves - (oldBranch ? oldBranch.totalTroves : 0);
    const diffTotalDebt = (branch.totalDebt - (oldBranch ? oldBranch.totalDebt : 0)) / newData.protocolConfig.decimalPrecision;
    const diffTotalCollateral = (branch.totalCollateral - (oldBranch ? oldBranch.totalCollateral : 0)) / (10 ** branch.decimals);
    const diffTCR = (branch.TCR - (oldBranch ? oldBranch.TCR : 0)) / newData.protocolConfig.decimalPrecision;
    const diffPrice = (branch.lastGoodPrice - (oldBranch ? oldBranch.lastGoodPrice : 0)) / newData.protocolConfig.decimalPrecision;
    const diffSPDeposits = (branch.stabilityPool.totalDeposits - (oldBranch ? oldBranch.stabilityPool.totalDeposits : 0)) / newData.protocolConfig.decimalPrecision;

    return [
      "  " + branch.index.toString(),
      cyan(branch.symbol),
      branch.totalTroves.toString(),
      (diffTotalTroves > 0 ? green(` (+${diffTotalTroves})`) : diffTotalTroves < 0 ? red(` (${diffTotalTroves})`) : ""),
      (branch.totalDebt / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffTotalDebt > 0 ? green(` (+${diffTotalDebt.toFixed(2)})`) : diffTotalDebt < 0 ? red(` (${diffTotalDebt.toFixed(2)})`) : ""),
      (branch.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      (diffTotalCollateral > 0 ? green(` (+${diffTotalCollateral.toFixed(2)})`) : diffTotalCollateral < 0 ? red(` (${diffTotalCollateral.toFixed(2)})`) : ""),
      stripAnsi(formattedTCR(branch.TCR, newData.protocolConfig.decimalPrecision, branch.CCR)),
      (diffTCR > 0 ? green(` (+${diffTCR.toFixed(2)})`) : diffTCR < 0 ? red(` (${diffTCR.toFixed(2)})`) : ""),
      (branch.lastGoodPrice / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffPrice > 0 ? green(` (+${diffPrice.toFixed(2)})`) : diffPrice < 0 ? red(` (${diffPrice.toFixed(2)})`) : ""),
      (branch.stabilityPool.totalDeposits / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffSPDeposits > 0 ? green(` (+${diffSPDeposits.toFixed(2)})`) : diffSPDeposits < 0 ? red(` (${diffSPDeposits.toFixed(2)})`) : ""),
    ];
  });

  ansiOutput += generateTable(headers, rows);

  newData.branches.forEach((branch) => {  
    const oldBranch = oldData.branches.find((oldBranch) => oldBranch.index === branch.index);
    const diffTotalTroves = branch.totalTroves - (oldBranch ? oldBranch.totalTroves : 0);
    const diffTotalDebt = (branch.totalDebt - (oldBranch ? oldBranch.totalDebt : 0)) / newData.protocolConfig.decimalPrecision;
    const diffTotalCollateral = (branch.totalCollateral - (oldBranch ? oldBranch.totalCollateral : 0)) / (10 ** branch.decimals);
    const diffTCR = (branch.TCR - (oldBranch ? oldBranch.TCR : 0)) / newData.protocolConfig.decimalPrecision;
    const diffPrice = (branch.lastGoodPrice - (oldBranch ? oldBranch.lastGoodPrice : 0)) / newData.protocolConfig.decimalPrecision;
    const diffShutdownTime = branch.shutdownTime - (oldBranch ? oldBranch.shutdownTime : 0);
    const diffActivePoolColl = (branch.activePool.totalCollateral - (oldBranch ? oldBranch.activePool.totalCollateral : 0)) / (10 ** branch.decimals);
    const diffActivePoolDebt = (branch.activePool.boldDebt - (oldBranch ? oldBranch.activePool.boldDebt : 0)) / newData.protocolConfig.decimalPrecision;
    const diffDefaultPoolColl = (branch.defaultPool.totalCollateral - (oldBranch ? oldBranch.defaultPool.totalCollateral : 0)) / (10 ** branch.decimals);
    const diffDefaultPoolDebt = (branch.defaultPool.boldDebt - (oldBranch ? oldBranch.defaultPool.boldDebt : 0)) / newData.protocolConfig.decimalPrecision;
    const diffCollSurplusColl = (branch.collSurplusPool.totalSurplus - (oldBranch ? oldBranch.collSurplusPool.totalSurplus : 0)) / newData.protocolConfig.decimalPrecision;
    const diffStabilityPoolTotal = (branch.stabilityPool.totalDeposits - (oldBranch ? oldBranch.stabilityPool.totalDeposits : 0)) / newData.protocolConfig.decimalPrecision;
    const diffStabilityPoolColl = (branch.stabilityPool.collBalance - (oldBranch ? oldBranch.stabilityPool.collBalance : 0)) / (10 ** branch.decimals);
    const diffStabilityPoolYieldGainsOwed = (branch.stabilityPool.yieldGainsOwed - (oldBranch ? oldBranch.stabilityPool.yieldGainsOwed : 0)) / newData.protocolConfig.decimalPrecision;
    const diffStabilityPoolYieldGainsPending = (branch.stabilityPool.yieldGainsPending - (oldBranch ? oldBranch.stabilityPool.yieldGainsPending : 0)) / newData.protocolConfig.decimalPrecision;

    ansiOutput += `\n${underline(bold(`Branch ${branch.index}: ${branch.collateral} (${branch.symbol})`))}\n\n`;

    ansiOutput += `  ${underline("Overall")}\n\n`;
    ansiOutput += `    ${bold("Troves:     ")} ${branch.totalTroves} `;
    if(diffTotalTroves !== 0) {
      ansiOutput += diffTotalTroves > 0 ? green(`(+${diffTotalTroves})`) : red(`(${diffTotalTroves})`);
    }
    ansiOutput += `\n    ${bold("Debt:       ")} ${yellow((branch.totalDebt / newData.protocolConfig.decimalPrecision).toFixed(2))} USDQ `;
    if(diffTotalDebt !== 0) {
      ansiOutput += diffTotalDebt > 0 ? green(`(+${diffTotalDebt.toFixed(2)})`) : red(`(${diffTotalDebt.toFixed(2)})`);
    }
    ansiOutput += `\n    ${bold("Collateral: ")} ${yellow((branch.totalCollateral / (10 ** branch.decimals)).toFixed(2))} ${branch.symbol} `;
    if(diffTotalCollateral !== 0) {
      ansiOutput += diffTotalCollateral > 0 ? green(`(+${diffTotalCollateral.toFixed(2)})`) : red(`(${diffTotalCollateral.toFixed(2)})`);
    }
    ansiOutput += `\n    ${bold("TCR:        ")} ${formattedTCR(branch.TCR, newData.protocolConfig.decimalPrecision, branch.CCR)} `;
    if(diffTCR !== 0) {
      ansiOutput += diffTCR > 0 ? green(`(+${diffTCR.toFixed(2)})`) : red(`(${diffTCR.toFixed(2)})`);
    }
    ansiOutput += `\n    ${bold("Price:      ")} ${(branch.lastGoodPrice / newData.protocolConfig.decimalPrecision).toFixed(2)} USD `;
    if(diffPrice !== 0) {
      ansiOutput += diffPrice > 0 ? green(`(+${diffPrice.toFixed(2)})`) : red(`(${diffPrice.toFixed(2)})`);
    }

    ansiOutput += `\n\n  ${underline("Pools")}\n\n`;

    const poolHeaders = [
      bold("    ActivePool"),
      "", //valueCollumn
      "", //diffCollumn
      bold("DefaultPool"),
      "", //valueCollumn
      "", //diffCollumn
      bold("CollSurplusPool"),
      "", //valueCollumn
      "", //diffCollumn
      bold("StabilityPool"),
      "", //valueCollumn
      "", //diffCollumn
    ];

    const poolRows: string[][] = [];

    poolRows.push([ "", "", "", "", "", "", "", "", "", "", "", "", ]);

    poolRows.push([
      italic("    Collateral"),
      (branch.activePool.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      (diffActivePoolColl > 0 ? green(` (+${diffActivePoolColl.toFixed(2)})`) : diffActivePoolColl < 0 ? red(` (${diffActivePoolColl.toFixed(2)})`) : ""),
      italic("Collateral"),
      (branch.defaultPool.totalCollateral / (10 ** branch.decimals)).toFixed(2),
      (diffDefaultPoolColl > 0 ? green(` (+${diffDefaultPoolColl.toFixed(2)})`) : diffDefaultPoolColl < 0 ? red(` (${diffDefaultPoolColl.toFixed(2)})`) : ""),
      italic("Collateral"),
      (branch.collSurplusPool.totalSurplus / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffCollSurplusColl > 0 ? green(` (+${diffCollSurplusColl.toFixed(2)})`) : diffCollSurplusColl < 0 ? red(` (${diffCollSurplusColl.toFixed(2)})`) : ""),
      italic("Collateral"),
      (branch.stabilityPool.collBalance / (10 ** branch.decimals)).toFixed(2),
      (diffStabilityPoolColl > 0 ? green(` (+${diffStabilityPoolColl.toFixed(2)})`) : diffStabilityPoolColl < 0 ? red(` (${diffStabilityPoolColl.toFixed(2)})`) : ""),
    ]);

    poolRows.push([
      italic("    Debt"),
      (branch.activePool.boldDebt / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffActivePoolDebt > 0 ? green(` (+${diffActivePoolDebt.toFixed(2)})`) : diffActivePoolDebt < 0 ? red(` (${diffActivePoolDebt.toFixed(2)})`) : ""),
      italic("Debt"),
      (branch.defaultPool.boldDebt / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffDefaultPoolDebt > 0 ? green(` (+${diffDefaultPoolDebt.toFixed(2)})`) : diffDefaultPoolDebt < 0 ? red(` (${diffDefaultPoolDebt.toFixed(2)})`) : ""),
      "", "", "",
      italic("Deposits"),
      (branch.stabilityPool.totalDeposits / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffStabilityPoolTotal > 0 ? green(` (+${diffStabilityPoolTotal.toFixed(2)})`) : diffStabilityPoolTotal < 0 ? red(` (${diffStabilityPoolTotal.toFixed(2)})`) : ""),
    ]);

    poolRows.push([
      "", "", "", "", "", "", "", "", "",
      italic("Yield Gains Owed"),
      (branch.stabilityPool.yieldGainsOwed / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffStabilityPoolYieldGainsOwed > 0 ? green(` (+${diffStabilityPoolYieldGainsOwed.toFixed(2)})`) : diffStabilityPoolYieldGainsOwed < 0 ? red(` (${diffStabilityPoolYieldGainsOwed.toFixed(2)})`) : ""),
    ]);

    poolRows.push([
      "", "", "", "", "", "", "", "", "",
      italic("Yield Gains Pending"),
      (branch.stabilityPool.yieldGainsPending / newData.protocolConfig.decimalPrecision).toFixed(2),
      (diffStabilityPoolYieldGainsPending > 0 ? green(` (+${diffStabilityPoolYieldGainsPending.toFixed(2)})`) : diffStabilityPoolYieldGainsPending < 0 ? red(` (${diffStabilityPoolYieldGainsPending.toFixed(2)})`) : ""),
    ]);

    ansiOutput += generateTable(poolHeaders, poolRows);

    ansiOutput += `\n  ${underline("Troves List")}\n\n`;


    if (branch.troves.length > 0) {
      const troveTableHeaders = [
        bold("    Trove ID"),
        bold("Owner"),
        bold("Debt (USDQ)"),
        bold(""), //diffDebt
        bold("Coll (" + branch.symbol + ")"),
        bold(""), //diffColl
        bold("Status"),
        bold("ICR"),
        bold(""), //diffICR
        bold("AIR (%)"),
        bold(""), //diffAIR
      ];
      const rows = branch.troves.map((trove) => {
        const oldTrove = oldBranch ? oldBranch.troves.find((oldTrove) => oldTrove.troveId === trove.troveId) : undefined;
        const diffDebt = oldTrove ? (trove.entireDebt - oldTrove.entireDebt) / newData.protocolConfig.decimalPrecision : 0;
        const diffColl = oldTrove ? (trove.entireColl - oldTrove.entireColl) / (10 ** branch.decimals) : 0;
        const diffICR = oldTrove ? (trove.ICR - oldTrove.ICR) / newData.protocolConfig.decimalPrecision : 0;
        const diffAIR = oldTrove ? (trove.annualInterestRate - oldTrove.annualInterestRate) / newData.protocolConfig.oneHundredPercent : 0;

        const troveIdReduced = trove.troveId.toString().slice(0, 8);
        return [
          oldTrove ? cyan("    " + troveIdReduced) : green("  " + troveIdReduced),
          cyan(trove.owner),
          (trove.entireDebt / newData.protocolConfig.decimalPrecision).toFixed(2),
          (diffDebt > 0 ? green(` (+${diffDebt.toFixed(2)})`) : diffDebt < 0 ? red(` (${diffDebt.toFixed(2)})`) : ""),
          (trove.entireColl / (10 ** branch.decimals)).toFixed(2),
          (diffColl > 0 ? green(` (+${diffColl.toFixed(2)})`) : diffColl < 0 ? red(` (${diffColl.toFixed(2)})`) : ""),
          trove.status + (oldTrove && oldTrove.status !== trove.status ? red(` (${oldTrove.status})`) : ""),
          formattedICR(trove.ICR, newData.protocolConfig.decimalPrecision, branch.MCR),
          (diffICR > 0 ? green(` (+${diffICR.toFixed(2)})`) : diffICR < 0 ? red(` (${diffICR.toFixed(2)})`) : ""),
          (trove.annualInterestRate / newData.protocolConfig.oneHundredPercent).toFixed(2),
          (diffAIR > 0 ? green(` (+${diffAIR.toFixed(2)})`) : diffAIR < 0 ? red(` (${diffAIR.toFixed(2)})`) : ""),
        ];
      });

      ansiOutput += generateTable(troveTableHeaders, rows);
    } else {
      ansiOutput += `    ${italic(red("No troves available."))}\n`;
    }
  });


  if(newData.owners.length > 0) {
    ansiOutput += `\n${underline(bold("Owners Balances"))}\n\n`;

    const ownerTableHeaders = [
      bold("  Owner"),
      bold("Alias"),
      bold("USDQ"),
      "", //diffUSDQ
    ];

    for (let i = 0; i < newData.branches.length; i++) {
      ownerTableHeaders.push(bold(`${newData.branches[i].symbol}`));
      ownerTableHeaders.push(""); //diffColl
    }

    const rows = newData.owners.map((owner) => {
      const oldOwner = oldData.owners.find(oldOwner => oldOwner.address === owner.address);
      const diffUSDQ = (owner.usdqBalance - (oldOwner ? oldOwner.usdqBalance : 0)) / newData.protocolConfig.decimalPrecision;

      let row = [
        cyan("  "+owner.address),
        ACTORS_LIST.find(actor => actor.address.toLowerCase() === owner.address.toLowerCase())?.name || "unknown",
        (owner.usdqBalance / newData.protocolConfig.decimalPrecision).toFixed(2),
        diffUSDQ > 0 ? green(`(+${diffUSDQ.toFixed(2)})`) : diffUSDQ < 0 ? red(`(${diffUSDQ.toFixed(2)})`) : "",
      ];

      for (let i = 0; i < newData.branches.length; i++) {
        const collat = owner.collaterals.find(collateral => collateral.index === i);
        const oldCollat = oldData.owners.find(oldOwner => oldOwner.address === owner.address)?.collaterals.find(collateral => collateral.index === i);
        const diffCollat = collat ? (collat.balance - (oldCollat ? oldCollat.balance : 0)) / (10 ** newData.branches[i].decimals) : 0;
        row.push(collat ? (collat.balance / (10 ** newData.branches[i].decimals)).toFixed(2) : "N/A");
        row.push(diffCollat > 0 ? green(`(+${diffCollat.toFixed(2)})`) : diffCollat < 0 ? red(`(${diffCollat.toFixed(2)})`) : "");
      }

      return row;
    });

    ansiOutput += generateTable(ownerTableHeaders, rows);
  }

  return ansiOutput;
}

export function generateAnsiFromFile(inputFile: string) {
  fs.readFile(inputFile, "utf-8", (err, jsonString) => {
    if (err) {
      console.error("Error reading file:", err);
      return;
    }
    try {
      const data: ProtocolSnapshot = parseSnapshot(jsonString);
      const ansiReport = generateAnsi(data);
      console.log(ansiReport);
    } catch (err) {
      console.error("Error parsing JSON:", err);
    }
  });
}

export function generateAnsiDiffFromFiles(oldFile: string, newFile: string) {
  fs.readFile(oldFile, "utf-8", (err, oldJsonString) => {
    if (err) {
      console.error("Error reading old file:", err);
      return;
    }
    fs.readFile(newFile, "utf-8", (err, newJsonString) => {
      if (err) {
        console.error("Error reading new file:", err);
        return;
      }
      try {
        const oldData: ProtocolSnapshot = parseSnapshot(oldJsonString);
        const newData: ProtocolSnapshot = parseSnapshot(newJsonString);

        const ansiDiff = generateAnsiDiff(oldData, newData);
        console.log(ansiDiff);
      } catch (err) {
        console.error("Error parsing JSON:", err);
      }
    });
  });
}