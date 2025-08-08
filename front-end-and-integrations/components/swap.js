import { useState, useEffect } from "react";
import {
  tokenContractAddress,
  tokenContractABI,
  swapContractABI,
  swapContractAddress,
  lendBorrowContractABI,
  lendBorrowContractAddress,
  usdtContractAddress,
  usdtContractABI,
  daiContractAddress,
  daiContractABI, 
} from "@/abiAndContractSettings";
  import { useWeb3ModalProvider, useWeb3ModalAccount } from '@web3modal/ethers/react'
  import { BrowserProvider, Contract, formatUnits, parseUnits } from 'ethers'

export default function SwapSection() { 
            // wallet connect settings
            const { address, chainId, isConnected } = useWeb3ModalAccount()
            const { walletProvider } = useWeb3ModalProvider()

            //loading state
            const [loading, setLoading] = useState()

          // lets read data for the Swap section using inbuilt functions and abi related read functions
           const [userHBARBalance, setuserHBARBalance] = useState()
           const [userUSDTBalance, setUserUSDTBalance] = useState()
           const [userDAIBalance, setUserDAIBalance] = useState()
           const [userHDFBalance, setUserHDFBalance] = useState()
    
           useEffect(()=>{
            const getTheData = async() => {
               if(isConnected){
                    //read settings first
                    const ethersProvider = new BrowserProvider(walletProvider) 
                    const usdtContractReadSettings = new Contract(usdtContractAddress, usdtContractABI, ethersProvider)
                    const daiContractReadSettings = new Contract(daiContractAddress, daiContractABI, ethersProvider)
                    const tokenContractReadSettings = new Contract(tokenContractAddress, tokenContractABI, ethersProvider)
              try {
                const HBARBalance = await ethersProvider.getBalance(address)
                const parseHBARBalance = parseFloat(formatUnits(HBARBalance, 18)).toFixed(5);
                console.log(parseHBARBalance.toString())
                setuserHBARBalance(parseHBARBalance.toString())
                const blockNumber = await ethersProvider.getBlockNumber();
                const block = await ethersProvider.getBlock(blockNumber);
                console.log("Current block timestamp:", block.timestamp);
                const USDTbalance = await usdtContractReadSettings.balanceOf(address)
                const parseUSDTbalance = parseFloat(formatUnits(USDTbalance, 18)).toFixed(5);
                console.log(parseUSDTbalance.toString())
                setUserUSDTBalance(parseUSDTbalance.toString())
                const DAIbalance = await daiContractReadSettings.balanceOf(address)
                const parseDAIbalance = parseFloat(formatUnits(DAIbalance, 18)).toFixed(5);
                console.log(parseDAIbalance.toString())
                setUserDAIBalance(parseDAIbalance.toString())
                const HDFbalance = await tokenContractReadSettings.balanceOf(address)
                const parseHDFbalance = parseFloat(formatUnits(HDFbalance, 18)).toFixed(5);
                console.log(parseHDFbalance.toString())
                setUserHDFBalance(parseHDFbalance.toString())
              } catch (error) {
                console.log(error)
              }
            }
            }
            getTheData();  
           }, [userHBARBalance, userUSDTBalance, userDAIBalance, userHDFBalance, address, loading])

        const [tokenA, setTokenA] = useState("0")
        const [tokenB, setTokenB] = useState("3")
        const [tokenAamount, setTokenAamount] = useState()
        const [sameTokenError, setSameTokenError] = useState(false)
        //Now we are going to write the Swap logic
        const SwapTokens = async () => {
          if(isConnected){
            setLoading(true)
            const ethersProvider = new BrowserProvider(walletProvider) 
            const signer = await ethersProvider.getSigner()
            const swapContractWriteSettings = new Contract(swapContractAddress, swapContractABI, signer)
           try {
            if (tokenA === "0" & tokenB !== "0"){
              const swapETHForTokens = await swapContractWriteSettings.swapEthForTokens(tokenB, {value:parseUnits(tokenAamount, 18)})}
            else if (tokenA !== "0" & tokenB === "0"){
              const swapTokensforETH = await swapContractWriteSettings.swapTokensForEth(tokenA, parseUnits(tokenAamount, 18))
            }
            else if (tokenA !== "0" & tokenB !== "0"){
              const swapTokensForTokens = await swapContractWriteSettings.swapTokensForTokens(tokenA, tokenB, parseUnits(tokenAamount, 18))
            }
            else if (tokenA === tokenB){
              setSameTokenError(true)
              setTimeout(() => {
               setSameTokenError(false)
              },5000)
            }
          } catch (error) {
            console.log(error)
            setLoading(false)
           }
           finally {
            setLoading(false)
           }
          }
        }

        //But we will first approve for tokens other than HBAR
        const approveTokens = async () => {
          if(isConnected){
          setLoading(true)
           const ethersProvider = new BrowserProvider(walletProvider) 
           const signer = await ethersProvider.getSigner()
           const swapContractWriteSettings = new Contract(swapContractAddress, swapContractABI, signer)
           const usdtContractWriteSettings = new Contract(usdtContractAddress, usdtContractABI, signer)
           const daiContractWriteSettings = new Contract(daiContractAddress, daiContractABI, signer)
           const tokenContractWriteSettings = new Contract(tokenContractAddress, tokenContractABI, signer)
           try {
            if (tokenA === "1" & tokenB !== "1"){
              const approveSwapToSpendUSDT = await usdtContractWriteSettings.approve(swapContractAddress, parseUnits(tokenAamount, 18))
            }
            else if (tokenA === "2" & tokenB !== "2"){
              const approveSwapToSpendDAI = await daiContractWriteSettings.approve(swapContractAddress, parseUnits(tokenAamount, 18))
            }
            else if (tokenA === "3" & tokenB !== "3"){
              const approveSwapToSpendHDF = await tokenContractWriteSettings.approve(swapContractAddress, parseUnits(tokenAamount, 18))
            }
            else if (tokenA === tokenB){
              setSameTokenError(true)
              setTimeout(() => {
               setSameTokenError(false)
              },5000)
            }
          } catch (error) {
            console.log(error)
            setLoading(false)
           }
           finally {
            setLoading(false)
           }
          }
        }

      
    return (
        <div>
        <div className="font-[500] bg-[#209] px-[0.4cm] py-[0.15cm] rounded-md mb-[0.2cm]" style={{display:"inline-block", boxShadow:"2px 2px 2px 2px #333"}}>Swap Tokens</div>
        <div className="text-[#ccc] text-[90%]">Swap your favorite tokens effortlessly using HederaFund's Swap feature</div>
      
        <div className="mt-[0.7cm] bg-[#000] p-[0.5cm] rounded-xl" style={{boxShadow:"2px 2px 2px 2px #333"}}>
        <div>
        <form>
        <div className="swapdiv bg-[#111] p-[0.5cm] rounded-xl " style={{boxShadow:"2px 2px 2px 2px #333"}}>
         <div className='p-[0.5cm] pb-[1cm] bg-[#eee] rounded-md'>
         <div className='text-[#222] font-[500] clear-both'>
          <select className="float-left outline-none bg-[#209] text-[#fff] p-[0.1cm]" onChange={(e) => setTokenA(e.target.value)}>
            <option value="0">HBAR</option>
            <option value="1">USDT</option>
            <option value="2">DAI</option>
            <option value="3">HDF</option>
          </select>
          <span className='float-right'>Token amount</span>
         </div>
         <div className='mt-[1.5cm] clear-both font-[500]'>
         <span className='text-[#000] float-left'>Bal: ≈ {tokenA == "0" && (<span>{userHBARBalance}</span>)} {tokenA == "1" && (<span>{userUSDTBalance}</span>)} {tokenA == "2" && (<span>{userDAIBalance}</span>)} {tokenA == "3" && (<span>{userHDFBalance}</span>)}</span>
         <input style={{display:"inline-block"}} className="w-[30%] float-right text-[120%] text-right bg-[#eee] outline-none text-[#000] placeholder-[#000]" type="text" id="tokenAamount" name="tokenAamount" onChange={(e) => setTokenAamount(e.target.value)} placeholder='0' />
         </div>
         </div>
        </div>
          <div className="switchdiv"><img src="images/swapimage.png" className="m-[auto] switchimage" width="30" /></div>
        <div className="swapdiv bg-[#111] p-[0.5cm] rounded-xl" style={{boxShadow:"2px 2px 2px 2px #333"}}>
         <div className='p-[0.5cm] pb-[1cm] bg-[#eee] rounded-md'>
         <div className='text-[#222] font-[500] clear-both'>
         <select className="float-left outline-none bg-[#209] text-[#fff] p-[0.1cm]" onChange={(e) => setTokenB(e.target.value)}>
            <option value="3">HDF</option>
            <option value="2">DAI</option>
            <option value="1">USDT</option>
            <option value="0">HBAR</option>
          </select>
          <span className='float-right'>Hedera Chain</span>
         </div>
         <div className='mt-[1.5cm] clear-both font-[500]'>
         <span className='text-[#000] float-left'>Bal: ≈ {tokenB == "0" && (<span>{userHBARBalance}</span>)} {tokenB == "1" && (<span>{userUSDTBalance}</span>)} {tokenB == "2" && (<span>{userDAIBalance}</span>)} {tokenB == "3" && (<span>{userHDFBalance}</span>)}</span>
         </div>
         </div>
        </div>
        {sameTokenError === true && (<div data-aos="slide-right" className="mt-[0.5cm] text-[#d7b644] text-[90%] text-center">Cannot swap same token</div>)}
        {tokenA != 0 ? (<button type="submit" className='text-center py-[0.3cm] bg-[#002] font-[500] text-[#fff] w-[100%] mt-[0.5cm] rounded-md generalbutton4 cursor-pointer' onClick={(e) => {e.preventDefault();approveTokens(tokenA, tokenAamount, tokenB)}}>Approve Swap</button>) : (<span></span>)}
        <button type="submit" className='text-center py-[0.3cm] bg-[#209] font-[500] text-[#fff] w-[100%] mt-[0.5cm] rounded-md generalbutton cursor-pointer' onClick={(e) => {e.preventDefault();SwapTokens(tokenA, tokenAamount, tokenB)}}>Swap Tokens</button>
        </form>
        </div>
        </div>

    {loading ? 
     (<div className='bg-[rgba(0,0,0,0.8)] text-[#000] text-center w-[100%] h-[100%] top-0 right-0' style={{position:"fixed", zIndex:"9999"}}>
      <div className='loader mx-[auto] xl:mt-[15%] lg:mt-[20%] md:mt-[30%] mt-[50%]'></div>
      </div>) : (<span></span>)  
     }
        
        </div>
    )
}