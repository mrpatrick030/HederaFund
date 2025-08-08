import '@/styles/globals.css'
import { Web3Modal } from '@/context/web3modal';
export const metadata = {
  title: 'HederaFund',
  description: 'Unlock Effortless Lending and Borrowing on the Hedera Ecosystem'
}

export default function App({ Component, pageProps }) {
  return  <Web3Modal> <Component {...pageProps} /> </Web3Modal>
}

 