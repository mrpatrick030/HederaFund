import { useState, useEffect } from "react";
import {
    tokenContractAddress,
    tokenContractABI,
    lendBorrowContractABI,
    lendBorrowContractAddress,
    usdtContractAddress,
    usdtContractABI,
    daiContractAddress,
    daiContractABI, 
  } from "@/abiAndContractSettings";
    import { useWeb3ModalProvider, useWeb3ModalAccount } from '@web3modal/ethers/react'
    import { BrowserProvider, Contract, formatUnits } from 'ethers'

    export default function MyBalancesSection({displayComponent, setDisplayComponent, changeBg3, changeBg4, changeBg5}) {
               // wallet connect settings
               const { address, chainId, isConnected } = useWeb3ModalAccount()
               const { walletProvider } = useWeb3ModalProvider()

              // lets read data for the Metrics section using inbuilt functions and abi related read functions
               const [HDFBalance, setHDFBalance] = useState()
               const [tokenPrice, setTokenPrice] = useState()
               const [userHBARbalance, setuserHBARbalance] = useState()
               const [userCreatedLoans, setuserCreatedLoans] = useState()
               const [userFundedLoans, setuserFundedLoans] = useState()
   
               useEffect(()=>{
                const getUserData = async() => {
                    if(isConnected){
                    //read settings first
                    const ethersProvider = new BrowserProvider(walletProvider) 
                    const tokenContractReadSettings = new Contract(tokenContractAddress, tokenContractABI, ethersProvider)
                    const usdtContractReadSettings = new Contract(usdtContractAddress, usdtContractABI, ethersProvider)
                    const daiContractReadSettings = new Contract(daiContractAddress, daiContractABI, ethersProvider)
                    const lendBorrowContractReadSettings = new Contract(lendBorrowContractAddress, lendBorrowContractABI, ethersProvider)
                  try {
                    const getHDFBalance = await tokenContractReadSettings.balanceOf(address)
                    console.log(getHDFBalance)
                    setHDFBalance(getHDFBalance.toString() * 10**-18)
                    setTokenPrice(parseFloat(0.000132).toFixed(10))
                    const HBARbalance = await ethersProvider.getBalance(address)   
                    console.log(HBARbalance)
                    setuserHBARbalance(formatUnits(HBARbalance, 18))
                    const userCreatedLoanArray = []
                    const userFundedLoanArray = []
                    const getAllLoannsNumber = await lendBorrowContractReadSettings.loanCount();
                    for (let i=0; i < getAllLoannsNumber; i++){
                      const allLoansData = await lendBorrowContractReadSettings.getLoanInfo(i);
                      if (allLoansData.borrower.toString().toLowerCase() === address.toLowerCase()){
                        userCreatedLoanArray.push(allLoansData)
                      }
                      else if (allLoansData.lender.toString().toLowerCase() === address.toLowerCase()){
                        userFundedLoanArray.push(allLoansData)
                      }
                    }
                    setuserCreatedLoans(userCreatedLoanArray.length)
                    setuserFundedLoans(userFundedLoanArray.length)
                  } catch (error) {
                    console.log(error)
                  }
                }
                }
                getUserData();  
               }, [isConnected, address])
    
    return (
        <div>
        <div className="font-[500] bg-[#209] px-[0.4cm] py-[0.15cm] rounded-md mb-[0.2cm]" style={{display:"inline-block", boxShadow:"2px 2px 2px 2px #333"}}>My Balances</div>
        <div className="text-[#ccc] text-[90%]">Manage all your assets on HederaFund</div>
        <div className="text-center mt-[0.4cm]">
            <div className="text-center m-[0.4cm]" style={{display:"inline-block"}}>
                <div className="font-[500] text-[110%]">HDF Balance</div>
                {HDFBalance > 0 ? (<div className="text-[#aaa]">{Intl.NumberFormat().format(parseFloat(HDFBalance).toFixed(10))} HDF</div>) : (<span>0</span>)}
            </div>
            <div className="text-center m-[0.4cm]" style={{display:"inline-block"}}>
                <div className="font-[500] text-[110%]">HDF Price</div>
                {tokenPrice ? (<div className="text-[#aaa]">≈ ${tokenPrice}</div>) : (<span>0</span>)}
            </div>
            <div className="text-center m-[0.4cm]" style={{display:"inline-block"}}>
                <div className="font-[500] text-[110%]">HBAR Balance</div>
                {userHBARbalance > 0 ? (<div className="text-[#aaa]">{parseFloat(userHBARbalance).toFixed(8)} HBAR</div>) : (<span>0</span>)}
            </div>
            <div className="text-center m-[0.4cm]" style={{display:"inline-block"}}>
                <div className="font-[500] text-[110%]">Loans you Created</div>
                {userCreatedLoans > 0 ? (<div className="text-[#aaa]">{Intl.NumberFormat().format(userCreatedLoans)}</div>) : (<span>0</span>)}
            </div>
            <div className="text-center m-[0.4cm]" style={{display:"inline-block"}}>
                <div className="font-[500] text-[110%]">Loans you Funded</div>
                {userFundedLoans > 0 ? (<div className="text-[#aaa]">{Intl.NumberFormat().format(userFundedLoans)}</div>) : (<span>0</span>)}
            </div>
        </div>
        <div className="grid lg:grid-cols-2 grid-cols-1 gap-4 mt-[1cm]">
            <div className="grid-cols-1 bg-[#000] p-[0.5cm] rounded-xl" style={{boxShadow:"2px 2px 2px 2px #333"}}>
                <div className="font-[500] text-[#fff] bg-[#209] px-[0.4cm] py-[0.1cm] rounded-md mb-[0.2cm]" style={{display:"inline-block"}}>$HDF</div>
               <div className="text-[#ccc] font-[500] underline">What is HDF?</div>
               <div className="text-[#aaa] text-[90%]">
               HDF serves as the core utility token within the HederaFund ecosystem. It plays a crucial role in the lending process, where users can use HDF as collateral when creating or securing loans on the platform. Beyond its functional role in lending, HDF is also positioned as a key incentive mechanism for the community. In line with our commitment to user engagement and platform growth, HDF will be distributed in future reward programs, including potential airdrops, to recognize and incentivize active community participation. Alternatively, you can purchase $HDF using the swap feature. As the ecosystem evolves, HDF will continue to be at the center of HederaFund's utility, governance, and reward structure.
               </div>
               <button onClick={(e) => setDisplayComponent("swaptokens") & changeBg5(e)} className="text-center px-[0.4cm] py-[0.2cm] bg-[#209] w-[100%] mt-[0.3cm] generalbutton text-[#fff] rounded-md">Buy HDF</button>
            </div>
            <div className="grid-cols-1 bg-[#000] p-[0.5cm] rounded-xl" style={{boxShadow:"2px 2px 2px 2px #333"}}>
                <div className="font-[500] text-[#fff] bg-[#209] px-[0.4cm] py-[0.1cm] rounded-md mb-[0.2cm]" style={{display:"inline-block"}}>P2P Lending/Borrowing</div>
                <div className="text-[#ccc] font-[500] underline">What is P2P lending/borrowing?</div>
                <div className="text-[#aaa] text-[90%]">
                On HederaFund, users can engage in P2P lending/borrowing using supported tokens through a decentralized and transparent system.
                The process begins when a borrower creates a loan request, specifying key details such as the loan amount, interest rate, expiry date, and the required collateral. Once submitted, another user, acting as the lender can choose to fund the loan. The borrower's collateral is securely locked by the system for the duration of the loan.
                If the borrower repays the loan along with the agreed interest before the expiry date, the collateral is returned. However, if the borrower fails to repay on time, the collateral can be claimed by the lender as compensation. In the event that no lender accepts the loan, the borrower retains the right to reclaim their locked collateral.
                </div>
                <button onClick={(e) => setDisplayComponent("lend") & changeBg3(e)} className="text-center px-[0.4cm] py-[0.2cm] lg:float-left bg-[#209] lg:w-[49%] w-[100%] mt-[0.3cm] generalbutton text-[#fff] rounded-md">Lend Now</button>
                <button onClick={(e) => setDisplayComponent("borrow") & changeBg4(e)} className="text-center px-[0.4cm] py-[0.2cm] lg:float-right bg-[#209] lg:w-[49%] w-[100%] mt-[0.3cm] generalbutton text-[#fff] rounded-md">Borrow Now</button>
            </div>
        </div>
        </div>
    )
}