import {Wallet, providers} from 'ethers'
import {Bcfg} from '@eth-optimism/core-utils'
import * as dotenv from 'dotenv'
import Config from 'bcfg'

/* Imports: Core */
import {AdminZkRandService} from '../admin'

dotenv.config()

const main = async () => {
    const config: Bcfg = new Config('zkRand')
    config.load({
        env: true,
        argv: true,
    })

    const env = process.env

    const THRESHOLD = config.uint("threshold", parseInt(env.THRESHOLD, 10))
    const NUMBER_OF_MEMBERS = config.uint("number_of_members", parseInt(env.NUMBER_OF_MEMBERS, 10))
    const DEGREE = config.uint("threshold", parseInt(env.DEGREE, 10))

    const L2_NODE_WEB3_URL = config.str('l2-node-web3-url', env.L2_NODE_WEB3_URL)
    const ADMIN_PRIVATE_KEY = config.str('admin-private-key', env.ADMIN_PRIVATE_KEY)

    // Optional
    const POLLING_INTERVAL = config.uint(
        'polling-interval',
        parseInt(env.POLLING_INTERVAL, 10) || 1000 * 12
    )

    // Optional
    const RAND_GEN_INTERVAL = config.uint(
        'polling-interval',
        parseInt(env.RAND_GEN_INTERVAL, 10) || 3600
    )

    const RAND_GEN_START_DATE = config.str('rand-gen-start-date', env.RAND_GEN_START_DATE)

    const ZK_RAND_ADDRESS = config.str('zk-rand-address', env.ZK_RAND_ADDRESS)
    const NODE_ONE_ADDRESS = config.str('node-one-address', env.NODE_ONE_ADDRESS)
    const NODE_TWO_ADDRESS = config.str('node-two-address', env.NODE_TWO_ADDRESS)
    const NODE_THREE_ADDRESS = config.str('node-three-address', env.NODE_THREE_ADDRESS)
    const NODE_FOUR_ADDRESS = config.str('node-four-address', env.NODE_FOUR_ADDRESS)
    const NODE_FIVE_ADDRESS = config.str('node-five-address', env.NODE_FIVE_ADDRESS)

    if (!L2_NODE_WEB3_URL) {
        throw new Error('Must pass L2_NODE_WEB3_URL')
    }

    const l2Provider = new providers.StaticJsonRpcProvider(L2_NODE_WEB3_URL)

    let wallet: Wallet
    wallet = new Wallet(ADMIN_PRIVATE_KEY, l2Provider)

    const chainId = (await l2Provider.getNetwork()).chainId

    const service = new AdminZkRandService({
        threshold: THRESHOLD,
        numberMembers: NUMBER_OF_MEMBERS,
        degree: DEGREE,
        l2RpcProvider: l2Provider,
        l2Wallet: wallet,
        chainId,
        zkRandAddress: ZK_RAND_ADDRESS,
        nodeOneAddress: NODE_ONE_ADDRESS,
        nodeTwoAddress: NODE_TWO_ADDRESS,
        nodeThreeAddress: NODE_THREE_ADDRESS,
        nodeFourAddress: NODE_FOUR_ADDRESS,
        nodeFiveAddress: NODE_FIVE_ADDRESS,
        pollingInterval: POLLING_INTERVAL,
        randGenInterval: RAND_GEN_INTERVAL,
        randGenStartDate: RAND_GEN_START_DATE,
    })

    await service.start()
}

if (require.main === module) {
    main()
}

export default main
