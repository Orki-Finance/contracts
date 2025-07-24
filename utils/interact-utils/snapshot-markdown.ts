import * as fs from 'fs';
import { ProtocolSnapshot, parseSnapshot } from './parse-snapshot';

const generateMarkdown = (data: ProtocolSnapshot): string => {
  let markdown = `# Protocol Snapshot Report

**Total Supply:** ${(data.totalSupply / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ  
**Number of Branches:** ${data.numberBranches}  
**Timestamp:** ${data.timestamp}  
**Block Number:** ${data.block}

**Overview**  

| Collateral | Total Troves | Total Debt (USDQ) | Total Collateral | TCR | Price (USD) | SP Deposits |
|------------|--------------|-------------------|------------------|-----|-------------| ----------- |
`;

  data.branches.forEach((branch) => {
    const tcrValue = branch.TCR / data.protocolConfig.decimalPrecision;
    const formattedTCR = tcrValue > 100 ? "N/A" : tcrValue.toFixed(2);
    markdown += `| ${branch.symbol} | ${branch.totalTroves} | ${(branch.totalDebt / data.protocolConfig.decimalPrecision).toFixed(2)} | ${(branch.totalCollateral / (10 ** branch.decimals)).toFixed(2)} | ${formattedTCR} | ${(branch.lastGoodPrice / data.protocolConfig.decimalPrecision).toFixed(2)} | ${(branch.stabilityPool.totalDeposits / data.protocolConfig.decimalPrecision).toFixed(2)} | \n`;
  });

  data.branches.forEach((branch) => {
    markdown += `## Branch ${branch.index}: ${branch.collateral} (${branch.symbol})  

### Overall  

- **Total Troves:** ${branch.totalTroves}  
- **Total Debt:** ${(branch.totalDebt / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ  
- **Total Collateral:** ${(branch.totalCollateral / (10 ** branch.decimals)).toFixed(2)} ${branch.symbol}   
- **Total Collateral Ratio (TCR):** ${(branch.TCR / data.protocolConfig.decimalPrecision).toFixed(2)}  
- **Shutdown Time:** ${branch.shutdownTime}  
- **Last Good Price:** ${(branch.lastGoodPrice / data.protocolConfig.decimalPrecision).toFixed(2)} USD
- **Active Pool**
  - **Total Collateral:** ${(branch.activePool.totalCollateral / (10 ** branch.decimals)).toFixed(2)} ${branch.symbol}
  - **Total Debt:** ${(branch.activePool.boldDebt / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
  - **Last Aggregation Update Time:** ${branch.activePool.lastAggUpdateTime}
- **Default Pool**
  - **Total Collateral:** ${(branch.defaultPool.totalCollateral / (10 ** branch.decimals)).toFixed(2)} ${branch.symbol}
  - **Total Debt:** ${(branch.defaultPool.boldDebt / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
- **Collateral Surplus Pool**
  - **Total Surplus:** ${(branch.collSurplusPool.totalSurplus / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
- **Stability Pool**
  - **Total Deposits:** ${(branch.stabilityPool.totalDeposits / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
  - **Yield Gains Pending:** ${(branch.stabilityPool.yieldGainsPending / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
  - **Yield Gains Owed:** ${(branch.stabilityPool.yieldGainsOwed / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ
  - **Collateral Balance:** ${(branch.stabilityPool.collBalance / (10 ** branch.decimals)).toFixed(2)} ${branch.symbol}

### Troves List  

`;

    if (branch.troves.length > 0) {
      markdown += `
**Overview**

| Trove ID | Entire Debt (USDQ) | Entire Collateral | Status | ICR | Annual Interest Rate |
|----------|--------------------|-------------------|--------|-----|----------------------|
`;
      branch.troves.forEach((trove) => {
        const troveIdReduced = trove.troveId.toString().slice(0, 6);
        markdown += `| ${troveIdReduced} | ${(trove.entireDebt / data.protocolConfig.decimalPrecision).toFixed(2)} | ${(trove.entireColl / (10 ** branch.decimals)).toFixed(2)} | ${trove.status} | ${(trove.ICR / data.protocolConfig.decimalPrecision).toFixed(2)} | ${(trove.annualInterestRate / data.protocolConfig.oneHundredPercent).toFixed(2)} | \n`;
      });
    }

    if (branch.troves.length > 0) {
      markdown += `\n**Details**\n<details>\n<summary>Click to expand</summary>\n\n`;
      branch.troves.forEach((trove) => {
        markdown += `- **Trove ID:** ${trove.troveId}  
  - **Entire Debt:** ${(trove.entireDebt / data.protocolConfig.decimalPrecision).toFixed(2)} USDQ    
  - **Entire Collateral:** ${(trove.entireColl  / (10 ** branch.decimals)).toFixed(2)} ${branch.symbol}    
  - **Status:** ${trove.status}  
  - **Individual Collateral Ratio (ICR):** ${(trove.ICR / data.protocolConfig.decimalPrecision).toFixed(2)}  
  - **Annual Interest Rate:** ${(trove.annualInterestRate / data.protocolConfig.oneHundredPercent).toFixed(2)}%  
  - **Owner:** ${trove.owner}  

`;
      });
      markdown += `</details>\n\n`;
    } else {
      markdown += `\n_No troves available._\n\n`;
    }
  });

  return markdown;
};

const diffValue = (
  oldValue: number,
  newValue: number,
  fractionDigits: number = 2,
  precision: number = 1,
  tokenDecimals: number = 0,
  
): string => {
  const factor = 10 ** tokenDecimals;
  const adjustedOldValue = oldValue / (precision * factor);
  const adjustedNewValue = newValue / (precision * factor);
  const delta = adjustedNewValue - adjustedOldValue;

  return delta === 0
    ? `${adjustedNewValue.toFixed(fractionDigits)}`
    : `${adjustedNewValue.toFixed(fractionDigits)} (${delta.toFixed(fractionDigits)})`;
};

const diffMarkdown = (oldData: ProtocolSnapshot, newData: ProtocolSnapshot): string => {
  let markdown = `# Protocol Diff Report

**Total Supply:** ${(newData.totalSupply / newData.protocolConfig.decimalPrecision).toFixed(2)} USDQ -- **${(newData.totalSupply - oldData.totalSupply) / newData.protocolConfig.decimalPrecision} USDQ** difference from the previous snapshot.
**Number of Branches:** ${newData.numberBranches} -- **${newData.numberBranches - oldData.numberBranches} branches** from the previous snapshot.
**Timestamp:** ${newData.timestamp} -- Time moved **${newData.timestamp - oldData.timestamp} seconds** from the previous snapshot.
**Block Number:** ${newData.block} -- **${newData.block - oldData.block} blocks** were mined from the previous snapshot.

**Overview**

| Collateral | Total Troves (delta) | Total Debt (USDQ) (delta) | Total Collateral (delta) | TCR  (delta) | Price (USD) (delta) | SP Deposits (delta) |
|------------|----------------------|---------------------------|--------------------------|--------------|---------------------|---------------------|
`;

  newData.branches.forEach((branch, index) => {
    const oldBranch = oldData.branches[index];
    const tcrValue = branch.TCR / newData.protocolConfig.decimalPrecision;
    const oldTCRValue = oldBranch.TCR / oldData.protocolConfig.decimalPrecision;
    markdown += `| ${branch.symbol}`;
    markdown += ` | ${diffValue(oldBranch.totalTroves, branch.totalTroves, 0)}`;
    markdown += ` | ${diffValue(oldBranch.totalDebt, branch.totalDebt, 2, newData.protocolConfig.decimalPrecision)}`;
    markdown += ` | ${diffValue(oldBranch.totalCollateral, branch.totalCollateral, 2, 1, branch.decimals)}`;
    markdown += tcrValue > 100 ? " | N/A" : ( oldTCRValue > 100 ? " | N/A" : " | " + diffValue(oldBranch.TCR, branch.TCR, 2, newData.protocolConfig.decimalPrecision) );
    markdown += ` | ${diffValue(oldBranch.lastGoodPrice, branch.lastGoodPrice, 2, newData.protocolConfig.decimalPrecision)}`;
    markdown += ` | ${diffValue(oldBranch.stabilityPool.totalDeposits, branch.stabilityPool.totalDeposits, 2, newData.protocolConfig.decimalPrecision)}`;
    markdown += " |\n";
    // | ${(branch.totalDebt / newData.protocolConfig.decimalPrecision).toFixed(2)} (${deltaTotalDebt}) | ${(branch.totalCollateral / (10 ** branch.decimals)).toFixed(2)} (${deltaTotalCollateral}) | ${formattedTCR} (${deltaTCR}) | ${(branch.lastGoodPrice / newData.protocolConfig.decimalPrecision).toFixed(2)} (${deltaPrice}) | ${(branch.stabilityPool.totalDeposits / newData.protocolConfig.decimalPrecision).toFixed(2)} (${deltaSPDeposits}) | \n`;
    
  });
  
  return markdown;
}

export function generateMarkdownFromFile(inputFile: string, outputFile: string) {
  fs.readFile(inputFile, "utf-8", (err, jsonString) => {
    if (err) {
      console.error("Error reading file:", err);
      return;
    }
    try {
      const data: ProtocolSnapshot = parseSnapshot(jsonString);
      const markdownReport = generateMarkdown(data);
      fs.writeFile(outputFile, markdownReport, (err) => {
        if (err) {
          console.error("Error writing markdown report:", err);
        } else {
          console.log(`Markdown report generated: ${outputFile}`);
        }
      });
    } catch (err) {
      console.error("Error parsing JSON:", err);
    }
  });
}

export function generateDiffMarkdownFromFiles(oldFile: string, newFile: string, outputFile: string) {
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
        const markdownReport = diffMarkdown(oldData, newData);
        fs.writeFile(outputFile, markdownReport, (err) => {
          if (err) {
            console.error("Error writing markdown report:", err);
          } else {
            console.log(`Markdown report generated: ${outputFile}`);
          }
        });
      } catch (err) {
        console.error("Error parsing JSON:", err);
      }
    });
  });
}